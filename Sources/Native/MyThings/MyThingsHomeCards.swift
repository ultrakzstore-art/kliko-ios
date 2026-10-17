import SwiftUI
import UIKit

/**
 «МОЙ ДОМ» — КАРТОЧКИ РАЗДЕЛОВ (владелец 16.10.2026: «ровная схема везде»; TestFlight 81: «вот эти моменты упростить»).

 «Пройдёт ли?» стоит на главном экране; остальные карточки — содержимое листа раздела (ЛистРазделаДома,
 MyThingsHomeSheets.swift), а на главном экране вместо них — по строке (КарточкаРазделаДома). Каждая карточка — как у
 «Моего» v1 (карточкаМоего, ЗаголовокМоего): строки того, что уже есть (касание — лист), и стандарты чипами для
 добавления одним касанием:
   · «Пройдёт ли?» — вещь шаблоном одним рядом (диван, холодильник, стиральная, шкаф, матрас, пианино) или «Свои
     размеры»; выбрали — поля Ш×В×Г, «разбирается» и итог по пути в дом (ПройдётЛиМоего, MyThingsHomePass.swift);
     пути нет — одна кнопка «Указать двери и лифт» (лист раздела проёмов);
   · проёмы — двери, лифт, лестница, этаж (частный дом или первый — 0) и «Лифта нет»; лифта нет в записи — типовой
     лифт и «1-й этаж или свой дом» одним касанием (было «Первой минутой» на главном экране);
   · кровати — частые спальные места чипами (90 / 140 / 160 / 180 × 200) кладут кровать сразу;
   · окна — шаблоны створок; ТВ на стене — из «Моих устройств» или новый; свет — цоколи картинками, касание — +1 лампа
     в выбранной комнате, счётчики «E27 ×6».
 Карточки получают ДомМоего значением и пишут через МоёХранилище.shared.обновитьДом — на хранилище не подписаны: экран
 или лист раздела перерисовывает их сам.
 */

// MARK: - Пройдёт ли

struct КарточкаПроходаДома: View {
    let дом: ДомМоего
    let открыть: (ЛистДомаМоего) -> Void
    @Environment(\.dynamicTypeSize) private var размерТекста
    @State private var ширина: Double? = nil
    @State private var высота: Double? = nil
    @State private var глубина: Double? = nil
    @State private var разбирается = false
    @State private var шаблон: String? = nil
    /// Выбрали вещь или «Свои размеры» — видны поля, «разбирается» и итог; до того карточка в три строки.
    @State private var открыто = false

    init(дом: ДомМоего, открыть: @escaping (ЛистДомаМоего) -> Void) {
        self.дом = дом
        self.открыть = открыть
    }

    private func т(_ ключ: String) -> String { МойДомText.т(ключ) }

    /// Частая крупная вещь: Ш×В×Г, см — примерно.
    struct ВещьШаблонаДома: Identifiable, Hashable {
        let id: String
        let ширина: Double
        let высота: Double
        let глубина: Double
        let значок: String
    }

    static let вещи: [ВещьШаблонаДома] = [
        ВещьШаблонаДома(id: "sofa3", ширина: 220, высота: 90, глубина: 95, значок: "sofa"),
        ВещьШаблонаДома(id: "sofa2", ширина: 160, высота: 85, глубина: 90, значок: "sofa"),
        ВещьШаблонаДома(id: "fridge", ширина: 60, высота: 185, глубина: 65, значок: "refrigerator"),
        ВещьШаблонаДома(id: "washer", ширина: 60, высота: 85, глубина: 55, значок: "washer"),
        ВещьШаблонаДома(id: "wardrobe", ширина: 120, высота: 220, глубина: 60, значок: "cabinet"),
        ВещьШаблонаДома(id: "mattress", ширина: 160, высота: 25, глубина: 200, значок: "bed.double"),
        ВещьШаблонаДома(id: "piano", ширина: 150, высота: 130, глубина: 60, значок: "pianokeys")
    ]

    private var вещь: ВещьПроходаМоего? {
        guard let ширина, let высота, let глубина else { return nil }
        return ВещьПроходаМоего(ширина: ширина, высота: высота, глубина: глубина, разбирается: разбирается)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ЗаголовокМоего(т("mh_pass_title"), значок: "shippingbox")
            Text(т("mh_pass_sub"))
                .font(.footnote)
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            рядВещей
            if открыто || вещь != nil {
                подробно
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .карточкаМоего()
        .animation(ДвижениеСайта.смена, value: вещь)
        .animation(ДвижениеСайта.смена, value: открыто)
    }

    /// Вещи шаблоном и «Свои размеры» — одним рядом с прокруткой вбок.
    private var рядВещей: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.вещи) { в in
                    ЧипМоего(т("mh_thing_" + в.id), выбран: шаблон == в.id, значок: в.значок) { подставить(в) }
                }
                ЧипМоего(т("mh_pass_own"), выбран: открыто && шаблон == nil, значок: "ruler") { своиРазмеры() }
            }
            .padding(.vertical, 1)
        }
    }

    private var подробно: some View {
        VStack(alignment: .leading, spacing: 12) {
            поля
            Toggle(isOn: $разбирается) {
                Text(т("mh_pass_knockdown"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.текст)
            }
            .tint(Theme.акцент)
            итог
        }
    }

    @ViewBuilder
    private var поля: some View {
        if размерТекста.isAccessibilitySize {
            VStack(spacing: 10) {
                поле(т("mh_w"), $ширина)
                поле(т("mh_h"), $высота)
                поле(т("mh_d"), $глубина)
            }
        } else {
            HStack(alignment: .top, spacing: 8) {
                поле(т("mh_w"), $ширина)
                поле(т("mh_h"), $высота)
                поле(т("mh_d"), $глубина)
            }
        }
    }

    private func поле(_ заголовок: String, _ значение: Binding<Double?>) -> some View {
        ПолеЧислаМоего(заголовок: заголовок, единица: т("mh_cm"), значение: Binding(get: { значение.wrappedValue },
                                                                                    set: { новое in
            значение.wrappedValue = новое
            шаблон = nil
        }), пределы: 1...600, знаков: 0)
    }

    /// Итог по пути в дом; пути нет (или он не нужен: первый этаж без входной двери) — приглашение указать двери.
    @ViewBuilder
    private var итог: some View {
        if let вещь, let проход = ПройдётЛиМоего.проверить(вещь, дом: дом) {
            ИтогПроходаВид(итог: проход)
                .id(ключИтога(вещь))
                .padding(12)
                .background(проход.уровень.краска.opacity(0.07),
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
        } else if дом.путьВДом.isEmpty || вещь != nil {
            VStack(alignment: .leading, spacing: 8) {
                Text(т("mh_pass_need_path"))
                    .font(.subheadline)
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
                МалаяКнопкаАвтоподбора(заголовок: т("mh_pass_set_path"), значок: "door.left.hand.open") {
                    ОткликСайта.выбор()
                    открыть(.раздел(.проёмы))
                }
            }
            .transition(.opacity)
        } else {
            Text(т("mh_pass_enter"))
                .font(.footnote)
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Ключ показа итога: сменились вещь или путь — итог проявляется заново.
    private func ключИтога(_ вещь: ВещьПроходаМоего) -> String {
        var ключ = вещь.подпись
        if вещь.разбирается { ключ += "+" }
        ключ += "|" + String(дом.проёмы.count)
        if дом.лифтаНет { ключ += "n" }
        return ключ
    }

    private func подставить(_ в: ВещьШаблонаДома) {
        ОткликСайта.выбор()
        открыто = true
        шаблон = в.id
        ширина = в.ширина
        высота = в.высота
        глубина = в.глубина
    }

    /// «Свои размеры»: поля открыты, введённое остаётся — только снимается выбор шаблона.
    private func своиРазмеры() {
        ОткликСайта.выбор()
        открыто = true
        шаблон = nil
    }
}

// MARK: - Проёмы

struct КарточкаПроёмовДома: View {
    let дом: ДомМоего
    let открыть: (ЛистДомаМоего) -> Void

    init(дом: ДомМоего, открыть: @escaping (ЛистДомаМоего) -> Void) {
        self.дом = дом
        self.открыть = открыть
    }

    private func т(_ ключ: String) -> String { МойДомText.т(ключ) }

    private var естьЛифт: Bool { дом.проёмы.contains { $0.вид == .лифт } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ЗаголовокМоего(т("mh_openings"), значок: "door.left.hand.open")
            Text(т("mh_openings_sub"))
                .font(.footnote)
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(дом.проёмы) { п in
                СтрокаДома(значок: п.вид.значок, заголовок: Self.заголовок(п), подпись: Self.подпись(п),
                           примерно: п.примерно) {
                    открыть(.проём(п, новый: false))
                }
            }
            if !естьЛифт && !дом.лифтаНет && дом.проёмы.count < ДомМоего.пределПроёмов {
                быстрыйЛифт
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            этаж
            if !естьЛифт {
                Toggle(isOn: Binding(get: { дом.лифтаНет }, set: { новое in
                    ОткликСайта.выбор()
                    МоёХранилище.shared.обновитьДом { д in д.лифтаНет = новое }
                })) {
                    Text(т("mh_no_lift"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.текст)
                }
                .tint(Theme.акцент)
            }
            if дом.проёмы.count < ДомМоего.пределПроёмов {
                ПотокЧипов(зазор: 8) {
                    ForEach(новые, id: \.self) { вид in
                        ЧипМоего(вид.название, выбран: false, значок: "plus") {
                            ОткликСайта.выбор()
                            открыть(.проём(ПроёмМоего(вид: вид), новый: true))
                        }
                    }
                }
            }
        }
        .карточкаМоего()
    }

    /// Лифт одним касанием (было «Первой минутой» на главном экране): «1-й этаж или свой дом» и типовые лифты —
    /// EN 81-70, «советский ≈», «грузовой ≈»; свой замер — чипом «+ Лифт» ниже.
    private var быстрыйЛифт: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(т("mh_first_lift"))
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.текстВторой)
            ПотокЧипов(зазор: 8) {
                ЧипМоего(т("mh_ground"), выбран: false, значок: "house") { первыйЭтаж() }
                ForEach(КаталогСтандартов.лифты) { лифт in
                    ЧипМоего(т("mh_lift_short_" + лифт.id), выбран: false, значок: "plus") { добавитьЛифт(лифт) }
                }
            }
        }
    }

    private func первыйЭтаж() {
        ОткликСайта.успех()
        МоёХранилище.shared.обновитьДом { д in
            д.лифтаНет = true
            д.этаж = 0
        }
    }

    private func добавитьЛифт(_ шаблон: КаталогСтандартов.ЛифтСтандарта) {
        ОткликСайта.успех()
        let лифт = ПроёмМоего.лифт(шаблон)
        МоёХранилище.shared.обновитьДом { д in
            guard д.проёмы.count < ДомМоего.пределПроёмов else { return }
            д.проёмы.append(лифт)
            д.лифтаНет = false
        }
    }

    /// Что ещё можно добавить: входная, лифт и лестница — по одной; двери — сколько угодно (до предела).
    private var новые: [ВидПроёмаМоего] {
        ВидПроёмаМоего.allCases.filter { вид in
            switch вид {
            case .входная, .лестница: return !дом.проёмы.contains { $0.вид == вид }
            case .лифт: return !естьЛифт && !дом.лифтаНет
            case .дверь, .балкон: return true
            }
        }
    }

    private var этаж: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(т("mh_floor"))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.текст)
                Text(т("mh_floor_hint"))
                    .font(.caption)
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            кнопкаЭтажа(-1)
            Text(Self.подписьЭтажа(дом.этаж))
                .font(.headline.monospacedDigit())
                .foregroundStyle(дом.этаж == nil ? Theme.текстВторой : Theme.текст)
                .frame(minWidth: 44)
                .multilineTextAlignment(.center)
                .contentTransition(.numericText(value: Double(дом.этаж ?? -1)))
            кнопкаЭтажа(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(т("mh_floor"))
        .accessibilityValue(Self.подписьЭтажа(дом.этаж))
        .accessibilityAdjustableAction { направление in
            switch направление {
            case .increment: сменитьЭтаж(1)
            case .decrement: сменитьЭтаж(-1)
            @unknown default: break
            }
        }
    }

    /// «—», «1-й / дом», «5».
    static func подписьЭтажа(_ этаж: Int?) -> String {
        guard let этаж else { return "—" }
        return этаж <= 1 ? МойДомText.т("mh_floor_ground") : String(этаж)
    }

    private func кнопкаЭтажа(_ на: Int) -> some View {
        Button {
            сменитьЭтаж(на)
        } label: {
            Image(systemName: на < 0 ? "minus" : "plus")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.акцент)
                .frame(width: 40, height: 40)
                .background(Theme.оттенокАкцента, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.9))
        .accessibilityHidden(true)
    }

    /// Этаж: нет → 1-й (0) → 2 → 3…; первый этаж и частный дом — 0 (лифт и лестница не нужны).
    private func сменитьЭтаж(_ на: Int) {
        let было = дом.этаж
        let стало: Int?
        if на > 0 {
            switch было {
            case nil: стало = 0
            case .some(let э) where э <= 1: стало = 2
            case .some(let э): стало = min(200, э + 1)
            }
        } else {
            switch было {
            case nil: стало = 0
            case .some(let э) where э <= 2: стало = 0
            case .some(let э): стало = э - 1
            }
        }
        guard стало != было else { return }
        ОткликСайта.выбор()
        let новый = стало
        МоёХранилище.shared.обновитьДом { д in д.этаж = новый }
    }

    static func заголовок(_ п: ПроёмМоего) -> String {
        let своё = п.имя.trimmingCharacters(in: .whitespacesAndNewlines)
        return своё.isEmpty ? п.вид.название : своё
    }

    /// «проход 74 см · высота 200 см»; лифт — «дверь 80 см · кабина 110×140 см»; лестница — «марш 105 см · поворот 90°».
    static func подпись(_ п: ПроёмМоего) -> String {
        let т = МойДомText.т
        var части: [String] = []
        switch п.вид {
        case .лифт:
            if let ш = п.ширина { части.append(String(format: т("mh_s_lift_door"), String(ш))) }
            if let кш = п.кабинаШирина, let кг = п.кабинаГлубина {
                части.append(String(format: т("mh_s_cabin"), String(кш) + "×" + String(кг)))
            }
        case .лестница:
            if let ш = п.ширина { части.append(String(format: т("mh_s_flight"), String(ш))) }
            части.append(ПоворотЛестницыМоего.из(п).название)
        default:
            if let ш = п.ширина { части.append(String(format: т("mh_s_clear"), String(ш))) }
            if let в = п.высота { части.append(String(format: т("mh_s_height"), String(в))) }
        }
        return части.isEmpty ? т("mh_s_empty") : части.joined(separator: " · ")
    }
}

// MARK: - Кровати

struct КарточкаКроватейДома: View {
    let дом: ДомМоего
    let открыть: (ЛистДомаМоего) -> Void

    init(дом: ДомМоего, открыть: @escaping (ЛистДомаМоего) -> Void) {
        self.дом = дом
        self.открыть = открыть
    }

    private func т(_ ключ: String) -> String { МойДомText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ЗаголовокМоего(т("mh_beds"), значок: "bed.double")
            ForEach(дом.кровати) { к in
                СтрокаДома(значок: "bed.double", заголовок: Self.заголовок(к), подпись: Self.подпись(к, дом)) {
                    открыть(.кровать(к, новая: false))
                }
            }
            if дом.кровати.isEmpty {
                Text(т("mh_beds_empty"))
                    .font(.footnote)
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if дом.кровати.count < ДомМоего.пределКроватей {
                ПотокЧипов(зазор: 8) {
                    ForEach(КаталогСтандартов.частыеСпальныеМеста, id: \.self) { место in
                        ЧипМоего(КаталогСтандартов.показ(место), выбран: false, значок: "plus") { добавить(место) }
                    }
                    ЧипМоего(т("mh_bed_other"), выбран: false, значок: "slider.horizontal.3") {
                        ОткликСайта.выбор()
                        открыть(.кровать(КроватьМоего(), новая: true))
                    }
                }
            }
        }
        .карточкаМоего()
    }

    private func добавить(_ место: String) {
        ОткликСайта.успех()
        МоёХранилище.shared.обновитьДом { д in
            guard д.кровати.count < ДомМоего.пределКроватей else { return }
            д.кровати.append(КроватьМоего(место: место))
        }
    }

    /// «Кровать 160×200».
    static func заголовок(_ к: КроватьМоего) -> String {
        guard let место = к.место else { return МойДомText.т("mh_bed") }
        return МойДомText.т("mh_bed") + " " + КаталогСтандартов.показ(место)
    }

    /// «матрас 20 см, независимые пружины · одеяло 200×220 · Спальня».
    static func подпись(_ к: КроватьМоего, _ дом: ДомМоего) -> String {
        let т = МойДомText.т
        var части: [String] = []
        var матрас: [String] = []
        if let в = к.матрасВысота { матрас.append(String(format: т("mh_s_mattress"), String(в))) }
        if let вид = к.матрас { матрас.append(т("mh_mt_" + вид).lowercased()) }
        if !матрас.isEmpty { части.append(матрас.joined(separator: ", ")) }
        if let одеяло = к.одеяло { части.append(String(format: т("mh_s_duvet"), КаталогСтандартов.показ(одеяло))) }
        if let комната = дом.имяКомнаты(к.комната) { части.append(комната) }
        return части.isEmpty ? т("mh_s_bed_more") : части.joined(separator: " · ")
    }
}

// MARK: - Окна

struct КарточкаОконДома: View {
    let дом: ДомМоего
    let открыть: (ЛистДомаМоего) -> Void

    init(дом: ДомМоего, открыть: @escaping (ЛистДомаМоего) -> Void) {
        self.дом = дом
        self.открыть = открыть
    }

    private func т(_ ключ: String) -> String { МойДомText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ЗаголовокМоего(т("mh_windows"), значок: "window.casement")
            Text(подзаголовок)
                .font(.footnote)
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(дом.окна) { о in
                СтрокаДома(значок: "window.casement", заголовок: Self.заголовок(о), подпись: Self.подпись(о, дом),
                           примерно: о.примерно) {
                    открыть(.окно(о, новое: false))
                }
            }
            if дом.окна.count < ДомМоего.пределОкон {
                ПотокЧипов(зазор: 8) {
                    ForEach(ШаблонОкнаДома.все) { ш in
                        ЧипМоего(ш.подпись, выбран: false, значок: "plus") {
                            ОткликСайта.выбор()
                            открыть(.окно(ОкноДомаМоего(ширина: ш.ширина, высота: ш.высота, створок: ш.створок,
                                                        примерно: true), новое: true))
                        }
                    }
                    ЧипМоего(т("mh_win_own"), выбран: false, значок: "ruler") {
                        ОткликСайта.выбор()
                        открыть(.окно(ОкноДомаМоего(), новое: true))
                    }
                }
            }
        }
        .карточкаМоего()
    }

    /// Потолок известен — «Потолок 270 см: шторы — 260–265».
    private var подзаголовок: String {
        guard let потолок = дом.потолок else { return т("mh_windows_sub") }
        let от = потолок - КаталогСтандартов.отступШтор.upperBound
        let до = потолок - КаталогСтандартов.отступШтор.lowerBound
        return т("mh_windows_sub") + " " + String(format: т("mh_curtains_by_ceiling"), String(потолок), String(от),
                                                  String(до))
    }

    static func заголовок(_ о: ОкноДомаМоего) -> String {
        guard let ш = о.ширина, let в = о.высота else { return МойДомText.т("mh_window") }
        return МойДомText.т("mh_window") + " " + String(ш) + "×" + String(в) + " " + МойДомText.т("mh_cm")
    }

    static func подпись(_ о: ОкноДомаМоего, _ дом: ДомМоего) -> String {
        var части: [String] = []
        if let н = о.створок { части.append(String(format: МойДомText.т("mh_s_sashes"), String(н))) }
        if let комната = дом.имяКомнаты(о.комната) { части.append(комната) }
        if о.примерно { части.append(МойДомText.т("mh_measure")) }
        return части.joined(separator: " · ")
    }
}

// MARK: - ТВ на стене

struct КарточкаЭкрановДома: View {
    let дом: ДомМоего
    let устройства: [УстройствоМоего]
    let открыть: (ЛистДомаМоего) -> Void

    init(дом: ДомМоего, устройства: [УстройствоМоего], открыть: @escaping (ЛистДомаМоего) -> Void) {
        self.дом = дом
        self.устройства = устройства
        self.открыть = открыть
    }

    private func т(_ ключ: String) -> String { МойДомText.т(ключ) }

    /// Экраны «Моих устройств» с диагональю, ещё не на стене.
    private var свободные: [УстройствоМоего] {
        let связанные = Set(дом.экраны.compactMap(\.устройство))
        return устройства.filter { $0.диагональ != nil && !связанные.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ЗаголовокМоего(т("mh_tvs"), значок: "tv")
            Text(т("mh_tvs_sub"))
                .font(.footnote)
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(дом.экраны) { э in
                СтрокаДома(значок: "tv", заголовок: Self.заголовок(э), подпись: Self.подпись(э, дом),
                           примерно: э.vesa == nil) {
                    открыть(.экран(э, новый: false))
                }
            }
            if дом.экраны.count < ДомМоего.пределЭкранов {
                ПотокЧипов(зазор: 8) {
                    ForEach(свободные) { у in
                        ЧипМоего(у.заголовок, выбран: false, значок: "plus") {
                            ОткликСайта.выбор()
                            открыть(.экран(ЭкранНаСтенеМоего(устройство: у.id, диагональ: у.диагональ), новый: true))
                        }
                    }
                    ЧипМоего(т("mh_tv_add"), выбран: false, значок: "plus") {
                        ОткликСайта.выбор()
                        открыть(.экран(ЭкранНаСтенеМоего(), новый: true))
                    }
                }
            }
        }
        .карточкаМоего()
    }

    /// «ТВ 55″ · VESA 300×300».
    static func заголовок(_ э: ЭкранНаСтенеМоего) -> String {
        var первая = МойДомText.т("mh_tv_short")
        if let д = э.диагональ { первая += " " + ЧислоМоего.дюймы(д) }
        var части = [первая]
        if let ш = э.шаблонДляСверки { части.append("VESA " + КаталогСтандартов.показ(ш.шаблон)) }
        return части.joined(separator: " · ")
    }

    static func подпись(_ э: ЭкранНаСтенеМоего, _ дом: ДомМоего) -> String {
        var части: [String] = []
        if э.vesa == nil && э.диагональ != nil { части.append(МойДомText.т("mh_s_vesa_usual")) }
        if let вес = э.вес { части.append(ЧислоМоего.ч(вес) + " " + МойДомText.т("mh_kg")) }
        if let комната = дом.имяКомнаты(э.комната) { части.append(комната) }
        return части.joined(separator: " · ")
    }
}

// MARK: - Свет

struct КарточкаСветаДома: View {
    let дом: ДомМоего
    @State private var комната: UUID? = nil
    @State private var все = false

    init(дом: ДомМоего) {
        self.дом = дом
    }

    private func т(_ ключ: String) -> String { МойДомText.т(ключ) }

    private var цоколи: [КаталогСтандартов.ЦокольСтандарта] {
        все ? КаталогСтандартов.цоколи : КаталогСтандартов.цоколи.filter(\.частый)
    }

    /// Низковольтные цоколи дома (12 В) — подсказка про трансформатор.
    private var низковольтные: [String] {
        Array(Set(дом.лампы.map(\.цоколь))).filter { КаталогСтандартов.цоколь($0)?.вольт == 12 }.sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ЗаголовокМоего(т("mh_light"), значок: "lightbulb")
            Text(т("mh_light_sub"))
                .font(.footnote)
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            ВыборКомнатыДома(комнаты: дом.комнаты, комната: $комната)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                ForEach(цоколи, id: \.id) { ц in
                    ПлиткаЦоколяДома(цоколь: ц, сколько: сколько(ц.id)) { добавить(ц.id) }
                }
            }
            Button {
                ОткликСайта.выбор()
                withAnimation(ДвижениеСайта.смена) { все.toggle() }
            } label: {
                Label(все ? т("mh_bases_less") : т("mh_bases_all"), systemImage: все ? "chevron.up" : "chevron.down")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.акцент)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(НажатиеКнопкиФото(сжатие: 0.96))
            ForEach(дом.лампы) { л in
                строка(л)
            }
            if !низковольтные.isEmpty {
                Label(String(format: т("mh_light_12v"), низковольтные.joined(separator: ", ")),
                      systemImage: "bolt.trianglebadge.exclamationmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.оранжевый)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .карточкаМоего()
    }

    private func сколько(_ код: String) -> Int {
        дом.лампы.filter { $0.цоколь == код && $0.комната == комната }.reduce(0) { $0 + $1.сколько }
    }

    private func добавить(_ код: String) {
        ОткликСайта.выбор()
        let где = комната
        МоёХранилище.shared.обновитьДом { д in
            if let i = д.лампы.firstIndex(where: { $0.цоколь == код && $0.комната == где }) {
                д.лампы[i].сколько = min(ЛампыМоего.пределыСколько.upperBound, д.лампы[i].сколько + 1)
            } else if д.лампы.count < ДомМоего.пределЛамп {
                д.лампы.append(ЛампыМоего(комната: где, цоколь: код, сколько: 1))
            }
        }
    }

    private func сменить(_ id: UUID, на: Int) {
        ОткликСайта.выбор()
        МоёХранилище.shared.обновитьДом { д in
            guard let i = д.лампы.firstIndex(where: { $0.id == id }) else { return }
            let стало = д.лампы[i].сколько + на
            if стало < 1 {
                д.лампы.remove(at: i)
            } else {
                д.лампы[i].сколько = min(ЛампыМоего.пределыСколько.upperBound, стало)
            }
        }
    }

    /// «E27 ×6 · Гостиная» с «−» и «+»; до нуля — строка уходит.
    private func строка(_ л: ЛампыМоего) -> some View {
        HStack(spacing: 10) {
            РисунокЦоколяДома(код: л.цоколь, размер: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(л.подпись)
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(Theme.текст)
                    .contentTransition(.numericText(value: Double(л.сколько)))
                Text(дом.имяКомнаты(л.комната) ?? т("mh_room_any"))
                    .font(.caption)
                    .foregroundStyle(Theme.текстВторой)
            }
            Spacer(minLength: 8)
            кнопка("minus") { сменить(л.id, на: -1) }
            кнопка("plus") { сменить(л.id, на: 1) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(л.цоколь + ", " + (дом.имяКомнаты(л.комната) ?? т("mh_room_any")))
        .accessibilityValue(String(л.сколько))
        .accessibilityAdjustableAction { направление in
            switch направление {
            case .increment: сменить(л.id, на: 1)
            case .decrement: сменить(л.id, на: -1)
            @unknown default: break
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func кнопка(_ значок: String, _ действие: @escaping () -> Void) -> some View {
        Button(action: действие) {
            Image(systemName: значок)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.акцент)
                .frame(width: 36, height: 36)
                .background(Theme.оттенокАкцента, in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.9))
    }
}

/// Плитка цоколя: картинка, код, пояснение («230 В, «миньон»») и число ламп в выбранной комнате. Касание — +1.
struct ПлиткаЦоколяДома: View {
    let цоколь: КаталогСтандартов.ЦокольСтандарта
    let сколько: Int
    let действие: () -> Void

    init(цоколь: КаталогСтандартов.ЦокольСтандарта, сколько: Int, действие: @escaping () -> Void) {
        self.цоколь = цоколь
        self.сколько = сколько
        self.действие = действие
    }

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
        Button(action: действие) {
            VStack(spacing: 4) {
                РисунокЦоколяДома(код: цоколь.id, размер: 34)
                Text(цоколь.id)
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(Theme.текст)
                Text(цоколь.пояснение)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.текстВторой)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 108, maxHeight: 108)
            .background(сколько > 0 ? Theme.оттенокАкцента : Theme.поверхность2, in: форма)
            .overlay { форма.strokeBorder(сколько > 0 ? Theme.акцент.opacity(0.5) : Theme.линия, lineWidth: 1) }
            .overlay(alignment: .topTrailing) {
                if сколько > 0 {
                    Text("×" + String(сколько))
                        .font(.caption2.weight(.heavy).monospacedDigit())
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.зелёный2, in: Capsule())
                        .padding(6)
                        .contentTransition(.numericText(value: Double(сколько)))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .contentShape(форма)
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.95))
        .animation(ДвижениеСайта.выбор, value: сколько)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(цоколь.id + ", " + цоколь.пояснение)
        .accessibilityValue(сколько > 0 ? String(сколько) : "")
        .accessibilityHint(МойДомText.т("mh_base_add_a11y"))
        .accessibilityAddTraits(.isButton)
    }
}
