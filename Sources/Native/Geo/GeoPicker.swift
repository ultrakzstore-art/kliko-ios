import SwiftUI
import UIKit

/**
 ЛИСТ «ГДЕ ИЩЕТЕ?» — ЭТАП 32 ПЕРЕХОДА НА SWIFTUI (владелец 25.09.2026: «почти 100% похоже на сайт»).

 Образец — выпадающий список города сайта на телефоне: разметка mkToggleCityDD и mkCityListHTML (js/marketplace.min.js),
 вид — часть «city-sheet» в css/marketplace-parts.min.css (#mk-city-dd). Сверху поле «Где ищете?» 46 pt на --mk-surf2
 (в фокусе — поверхность и зелёная кромка 2 pt) и круглое «×»; под ним строка с зелёным кругом — у сайта там «Рядом со
 мной», у нас «Определить автоматически» (api/geo_ip.php, ВыборГорода.определить). Дальше чипы: недавние (с часами,
 до трёх), «Очистить» пунктиром и быстрые — три города и первый город каждой области; «По всей стране» жирно акцентом;
 области строками с «вся область» и кнопкой раскрытия 36 pt, под ней — города области с зелёной чертой слева. Выбранная
 строка — оттенок акцента, черта 3 pt слева и зелёный текст.

 Своё поверх сайта: районы Астаны, Алматы и Шымкента (MK_GEO_DISTRICTS; у сайта они в фильтрах, а не в этом списке) —
 поэтому три города идут отдельными строками «Крупные города» с раскрытием в районы, а области — под «Регион». Поиск —
 как у сайта: по названиям областей и городов (и районов), с вариантами запроса в латинской раскладке и латиницей
 (ГеоПоиск), найденное подсвечено; ничего — «Такого места не нашли». Нажатие выбирает и закрывает лист.
 */
struct ЛистГорода: View {
    @ObservedObject private var выбор = ВыборГорода.shared
    @Environment(\.dismiss) private var закрыть
    @Environment(\.accessibilityReduceMotion) private var безДвижения
    @State private var запрос = ""
    /// Раскрытые города и области — по ключу региона (_mkCityOpen сайта).
    @State private var раскрыто: Set<String> = []
    @FocusState private var полеВФокусе: Bool

    init() {}

    var body: some View {
        VStack(spacing: 0) {
            ПолеГорода(текст: $запрос, фокус: $полеВФокусе, закрыть: { закрыть() })
            СтрокаОпределения(определяем: выбор.определяем, неудача: выбор.неОпределили, действие: { определить() })
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if варианты.isEmpty {
                        обзор
                    } else {
                        найденное
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .background(Theme.поверхность)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.поверхность)
        .presentationCornerRadius(Theme.Радиус.шапка)
        .onAppear { раскрытьВыбранное() }
    }

    /// Варианты набранного (mkQueryCands); пусто — список без поиска.
    private var варианты: [String] { ГеоПоиск.варианты(запрос) }

    // MARK: - Без поиска

    @ViewBuilder
    private var обзор: some View {
        ЧипыМест(недавние: выбор.недавние, быстрые: быстрыеМеста, где: выбор.где,
                 выбрать: { место in выбратьМесто(место) }, очистить: { выбор.очиститьНедавние() })
        СтрокаМеста(название: AttributedString(DesignText.т("all_kz")), пометка: nil, уровень: .всё,
                    выбрана: выбор.где.повсюду, раскрыта: nil, подписьРаскрытия: "",
                    выбрать: { выбратьГде(ГдеИскать(), место: nil) }, раскрыть: {})
        ЗаголовокГео(текст: GeoText.т("big_cities"))
        ForEach(ГеоДанные.городаРеспублики) { регион in
            строкиГорода(регион)
        }
        ЗаголовокГео(текст: GeoText.т("regions"))
        ForEach(ГеоДанные.области) { регион in
            строкиОбласти(регион)
        }
    }

    /// Город с районами: сам город (все районы) и, раскрытым, — его районы.
    @ViewBuilder
    private func строкиГорода(_ регион: ГеоРегион) -> some View {
        let районы = ГеоДанные.районыГорода(регион.название)
        let открыт = раскрыто.contains(регион.ключ)
        СтрокаМеста(название: AttributedString(регион.название), пометка: nil, уровень: .регион,
                    выбрана: выбор.где.город == регион.название && выбор.где.район.isEmpty,
                    раскрыта: районы.isEmpty ? nil : открыт,
                    подписьРаскрытия: String(format: GeoText.т("show_districts"), регион.название),
                    выбрать: { выбратьМесто(НедавнееМесто(вид: .город, значение: регион.название)) },
                    раскрыть: { переключить(регион.ключ) })
        if открыт {
            ForEach(районы) { район in
                СтрокаМеста(название: AttributedString(район.название), пометка: nil, уровень: .вложенное,
                            выбрана: выбор.где.район == район.ключ, раскрыта: nil, подписьРаскрытия: "",
                            выбрать: { выбратьМесто(НедавнееМесто(вид: .район, значение: район.ключ)) },
                            раскрыть: {})
            }
        }
    }

    /// Область: вся область (region=) и, раскрытой, — её города (city=). Раскрытие — только если городов больше одного,
    /// как у сайта.
    @ViewBuilder
    private func строкиОбласти(_ регион: ГеоРегион) -> some View {
        let открыт = раскрыто.contains(регион.ключ)
        СтрокаМеста(название: AttributedString(регион.название), пометка: GeoText.т("oblast_all"), уровень: .регион,
                    выбрана: выбор.где.регион == регион.ключ,
                    раскрыта: регион.города.count > 1 ? открыт : nil,
                    подписьРаскрытия: String(format: GeoText.т("show_cities"), регион.название),
                    выбрать: { выбратьМесто(НедавнееМесто(вид: .регион, значение: регион.ключ)) },
                    раскрыть: { переключить(регион.ключ) })
        if открыт {
            ForEach(регион.города, id: \.self) { город in
                СтрокаМеста(название: AttributedString(город), пометка: nil, уровень: .вложенное,
                            выбрана: выбор.где.город == город, раскрыта: nil, подписьРаскрытия: "",
                            выбрать: { выбратьМесто(НедавнееМесто(вид: .город, значение: город)) },
                            раскрыть: {})
            }
        }
    }

    /// Быстрые чипы — _mkGeoChipsHTML: три города и первый город каждой области. Сайт перемешивает их при каждом
    /// открытии; у нас — порядок справочника, чтобы свой город не приходилось искать заново.
    private var быстрыеМеста: [НедавнееМесто] {
        ГеоДанные.регионы.compactMap { регион -> НедавнееМесто? in
            let имя = регион.город ? регион.название : (регион.города.first ?? "")
            return имя.isEmpty ? nil : НедавнееМесто(вид: .город, значение: имя)
        }
    }

    // MARK: - Поиск

    @ViewBuilder
    private var найденное: some View {
        let итоги = НайденноеМесто.искать(варианты)
        if итоги.isEmpty {
            НичегоНеНашли()
        } else {
            ForEach(итоги) { строка in
                СтрокаМеста(название: подсвеченное(строка.название, строка.подсветка, вложенное: строка.уровень == .вложенное),
                            пометка: строка.пометка, уровень: строка.уровень,
                            выбрана: строка.выбрана(выбор.где), раскрыта: nil, подписьРаскрытия: "",
                            выбрать: { выбратьГде(строка.где, место: строка.место) }, раскрыть: {})
            }
        }
    }

    /// Найденное в названии — зелёным и жирнее (<mark> сайта: --mk-green2, 800).
    private func подсвеченное(_ название: String, _ подсветка: Range<Int>?, вложенное: Bool) -> AttributedString {
        let символы = Array(название)
        guard let диапазон = подсветка, !диапазон.isEmpty, диапазон.lowerBound >= 0,
              диапазон.upperBound <= символы.count, название.lowercased().count == символы.count else {
            return AttributedString(название)
        }
        var итог = AttributedString(String(символы[..<диапазон.lowerBound]))
        var метка = AttributedString(String(символы[диапазон]))
        метка.foregroundColor = Theme.зелёный2
        метка.font = Font.system(size: вложенное ? 14 : 15, weight: .heavy)
        итог.append(метка)
        итог.append(AttributedString(String(символы[диапазон.upperBound...])))
        return итог
    }

    // MARK: - Действия

    private func выбратьГде(_ новое: ГдеИскать, место: НедавнееМесто?) {
        выбор.выбрать(новое, запомнить: место)
        закрыть()
    }

    private func выбратьМесто(_ место: НедавнееМесто) {
        guard let новое = место.где else { return }
        выбратьГде(новое, место: место)
    }

    private func переключить(_ ключ: String) {
        withAnimation(безДвижения ? nil : ДвижениеСайта.смена) {
            раскрыто.formSymmetricDifference([ключ])
        }
    }

    /// Выбран район или город области — его город или область уже раскрыты: видно, где выбранное.
    private func раскрытьВыбранное() {
        let текущее = выбор.где
        if let район = ГеоДанные.район(текущее.район), let город = ГеоДанные.регионГорода(район.город) {
            раскрыто.insert(город.ключ)
        } else if !текущее.город.isEmpty, let область = ГеоДанные.областьГорода(текущее.город) {
            раскрыто.insert(область.ключ)
        }
    }

    /// «Определить автоматически»: нашёлся город — он выбран, лист закрывается; нет — подпись под кнопкой.
    private func определить() {
        полеВФокусе = false
        Task {
            if await выбор.определить() { закрыть() }
        }
    }
}

// MARK: - Краски

private enum КраскиГео {
    /// Чипы, «×» и кнопка раскрытия: --mk-surf2, в тёмной — белый 6 % поверх поверхности (color-mix сайта).
    static let фонЧипа = Theme.цвет(светлый: Theme.hex(0xF4F8F6),
                                    тёмный: Theme.смесь(Theme.hex(0xFFFFFF), Theme.hex(0x16161F), 0.06))
    /// Выбранный чип: --mk-green2 светлой темы (#1d7d4a) в обеих — белый текст на тёмном #34c997 не читается (этап 31).
    static let выбранныйЧип = Color(uiColor: Theme.hex(0x1D7D4A))
}

// MARK: - Найденное

/// Уровень строки списка.
private enum УровеньСтроки {
    /// «По всей стране» — жирно акцентом (.mk-city-all).
    case всё
    /// Город или область (.mk-city-reg): жирная строка с линией сверху.
    case регион
    /// Город области или район (.mk-city-sub): с отступом и зелёной чертой слева.
    case вложенное
}

/// Строка найденного: область или город и под ними — совпавшие города или районы, как в mkCityListHTML с запросом.
private struct НайденноеМесто: Identifiable {
    let id: String
    let название: String
    /// Какие символы названия совпали; nil — строка попала ради совпавших под ней.
    let подсветка: Range<Int>?
    let пометка: String?
    let уровень: УровеньСтроки
    let где: ГдеИскать
    let место: НедавнееМесто

    func выбрана(_ текущее: ГдеИскать) -> Bool {
        switch место.вид {
        case .город:
            return текущее.город == где.город && (уровень == .вложенное || текущее.район.isEmpty)
        case .регион:
            return текущее.регион == где.регион && текущее.город.isEmpty
        case .район:
            return текущее.район == где.район
        }
    }

    /// Все совпадения по справочнику в его порядке.
    static func искать(_ варианты: [String]) -> [НайденноеМесто] {
        var итог: [НайденноеМесто] = []
        guard !варианты.isEmpty else { return итог }
        for регион in ГеоДанные.регионы {
            if регион.город {
                добавитьГород(регион, варианты, в: &итог)
            } else {
                добавитьОбласть(регион, варианты, в: &итог)
            }
        }
        return итог
    }

    private static func добавитьГород(_ регион: ГеоРегион, _ варианты: [String], в итог: inout [НайденноеМесто]) {
        let вИмени = ГеоПоиск.найти(регион.название, варианты)
        var районы: [НайденноеМесто] = []
        for район in ГеоДанные.районыГорода(регион.название) {
            guard let совпало = ГеоПоиск.найти(район.название, варианты) else { continue }
            районы.append(НайденноеМесто(id: "d:" + район.ключ, название: район.название, подсветка: совпало,
                                         пометка: nil, уровень: .вложенное,
                                         где: ГдеИскать(город: район.город, район: район.ключ),
                                         место: НедавнееМесто(вид: .район, значение: район.ключ)))
        }
        guard вИмени != nil || !районы.isEmpty else { return }
        итог.append(НайденноеМесто(id: "c:" + регион.название, название: регион.название, подсветка: вИмени,
                                   пометка: nil, уровень: .регион, где: ГдеИскать(город: регион.название),
                                   место: НедавнееМесто(вид: .город, значение: регион.название)))
        итог.append(contentsOf: районы)
    }

    private static func добавитьОбласть(_ регион: ГеоРегион, _ варианты: [String], в итог: inout [НайденноеМесто]) {
        let вИмени = ГеоПоиск.найти(регион.название, варианты)
        var города: [НайденноеМесто] = []
        for город in регион.города {
            guard let совпало = ГеоПоиск.найти(город, варианты) else { continue }
            города.append(НайденноеМесто(id: "c:" + регион.ключ + ":" + город, название: город, подсветка: совпало,
                                         пометка: nil, уровень: .вложенное, где: ГдеИскать(город: город),
                                         место: НедавнееМесто(вид: .город, значение: город)))
        }
        guard вИмени != nil || !города.isEmpty else { return }
        итог.append(НайденноеМесто(id: "r:" + регион.ключ, название: регион.название, подсветка: вИмени,
                                   пометка: GeoText.т("oblast_all"), уровень: .регион,
                                   где: ГдеИскать(регион: регион.ключ),
                                   место: НедавнееМесто(вид: .регион, значение: регион.ключ)))
        итог.append(contentsOf: города)
    }
}

// MARK: - Части листа

/// Поле «Где ищете?» (.mk-city-qw) и круглое «×» (.mk-city-hd button).
private struct ПолеГорода: View {
    @Binding var текст: String
    let фокус: FocusState<Bool>.Binding
    let закрыть: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            поле
            Button(action: закрыть) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.текстВторой)
                    .frame(width: 44, height: 44)
                    .background(КраскиГео.фонЧипа, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(GeoText.т("close"))
        }
        .padding(.horizontal, 14)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }

    private var вФокусе: Bool { фокус.wrappedValue }

    private var поле: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.текстВторой)
                .accessibilityHidden(true)
            TextField(GeoText.т("placeholder"), text: $текст,
                      prompt: Text(GeoText.т("placeholder")).foregroundColor(Theme.текстВторой))
                .font(.system(size: 16))
                .foregroundStyle(Theme.текст)
                .tint(Theme.акцент)
                .focused(фокус)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !текст.isEmpty {
                Button { текст = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.текстВторой)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(DesignText.т("clear"))
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: 46)
        .frame(maxWidth: .infinity)
        .background(вФокусе ? Theme.поверхность : Theme.поверхность2,
                    in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(вФокусе ? Theme.зелёный2 : Theme.линия, lineWidth: вФокусе ? 2 : 1)
        }
    }
}

/// «Определить автоматически» — в виде строки .mk-city-nearrow: зелёный круг 40 pt со значком, жирная надпись, под ней —
/// «Определяем…» или «Не удалось определить город…».
private struct СтрокаОпределения: View {
    let определяем: Bool
    let неудача: Bool
    let действие: () -> Void

    var body: some View {
        Button(action: действие) {
            HStack(spacing: 12) {
                значок
                VStack(alignment: .leading, spacing: 1) {
                    Text(GeoText.т("detect"))
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Theme.текст)
                    if let подпись {
                        Text(подпись)
                            .font(.system(size: 12))
                            .foregroundStyle(неудача ? Theme.малиновый : Theme.текстВторой)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(фон, in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                    .strokeBorder(Theme.зелёный2.opacity(0.22), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(определяем)
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private var значок: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Theme.зелёный2, Theme.зелёный], startPoint: .topLeading,
                                     endPoint: .bottomTrailing))
            if определяем {
                SiteSpinner.белый
            } else {
                Image(systemName: "location.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
        }
        .frame(width: 40, height: 40)
        .accessibilityHidden(true)
    }

    private var подпись: String? {
        if определяем { return GeoText.т("detecting") }
        if неудача { return GeoText.т("detect_fail") }
        return nil
    }

    /// linear-gradient(135deg, green2 12 % → поверхность к 80 %).
    private var фон: LinearGradient {
        LinearGradient(colors: [Theme.зелёный2.opacity(0.12), Theme.поверхность], startPoint: .topLeading,
                       endPoint: UnitPoint(x: 0.8, y: 0.8))
    }
}

/// Чипы сверху списка (.mk-geo-chips): недавние, «Очистить», быстрые — листаются вбок.
private struct ЧипыМест: View {
    let недавние: [НедавнееМесто]
    let быстрые: [НедавнееМесто]
    let где: ГдеИскать
    let выбрать: (НедавнееМесто) -> Void
    let очистить: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(недавние, id: \.self) { место in
                    ЧипГорода(название: место.название, недавний: true, выбран: место.где == где) { выбрать(место) }
                }
                if !недавние.isEmpty {
                    ЧипОчистить(действие: очистить)
                }
                ForEach(быстрыеБезНедавних, id: \.self) { место in
                    ЧипГорода(название: место.название, недавний: false, выбран: где.город == место.значение) {
                        выбрать(место)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .padding(.bottom, 12)
        }
    }

    /// Быстрый чип, который уже есть среди недавних, второй раз не показываем (как сайт — по ключу «вид:значение»).
    private var быстрыеБезНедавних: [НедавнееМесто] {
        быстрые.filter { !недавние.contains($0) }
    }
}

/// Чип места (.mk-geo-chip): пилюля 38 pt, у быстрого — зелёная точка, у недавнего — часы; выбранный — залит зелёным.
private struct ЧипГорода: View {
    let название: String
    let недавний: Bool
    let выбран: Bool
    let действие: () -> Void

    var body: some View {
        Button(action: действие) {
            HStack(spacing: 6) {
                if недавний {
                    Image(systemName: "clock")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(выбран ? Color.white : Theme.текстВторой)
                } else {
                    Circle()
                        .fill(выбран ? Color.white : Theme.зелёный2)
                        .frame(width: 7, height: 7)
                }
                Text(название)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(выбран ? Color.white : Theme.текст)
                    .lineLimit(1)
            }
            .padding(.leading, 12)
            .padding(.trailing, 14)
            .frame(height: 38)
            .background(выбран ? КраскиГео.выбранныйЧип : КраскиГео.фонЧипа, in: Capsule())
            .overlay {
                Capsule().strokeBorder(выбран ? Color.clear : Theme.линия.opacity(0.6), lineWidth: 1)
            }
            // .mk-geo-chip.on: 0 6px 14px -8px rgba(15,81,50,.8)
            .shadow(color: выбран ? Color(uiColor: Theme.hex(0x0F5132, 0.5)) : .clear, radius: 5, x: 0, y: 4)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(выбран ? .isSelected : [])
        .accessibilityHint(недавний ? GeoText.т("recent") : "")
    }
}

/// «Очистить» недавние (.mk-geo-clear): пунктирная пилюля серым.
private struct ЧипОчистить: View {
    let действие: () -> Void

    var body: some View {
        Button(action: действие) {
            HStack(spacing: 6) {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .semibold))
                Text(GeoText.т("clear"))
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(Theme.текстВторой)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .overlay {
                Capsule().strokeBorder(Theme.текстВторой.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Строка списка: название (и «вся область» под ним), справа — раскрытие, если есть что раскрывать.
private struct СтрокаМеста: View {
    let название: AttributedString
    let пометка: String?
    let уровень: УровеньСтроки
    let выбрана: Bool
    /// nil — раскрывать нечего; иначе — раскрыта ли.
    let раскрыта: Bool?
    let подписьРаскрытия: String
    let выбрать: () -> Void
    let раскрыть: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: выбрать) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(название)
                        .font(.system(size: размер, weight: насыщенность))
                        .foregroundStyle(цветТекста)
                        .multilineTextAlignment(.leading)
                    if let пометка {
                        Text(пометка)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.текстВторой)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: уровень == .регион ? 36 : nil, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(выбрана ? .isSelected : [])
            if let раскрыта {
                КнопкаРаскрытия(раскрыта: раскрыта, подпись: подписьРаскрытия, действие: раскрыть)
            }
        }
        .padding(.leading, уровень == .вложенное ? 36 : 16)
        .padding(.trailing, уровень == .регион ? 12 : 16)
        // .mk-city-opt 12/16, .mk-city-reg 10 (под кнопку раскрытия 36), .mk-city-sub 10
        .padding(.vertical, уровень == .всё ? 12 : 10)
        .background(выбрана ? Theme.оттенокАкцента : Color.clear)
        .overlay(alignment: .leading) { черта }
        .overlay(alignment: .top) { линияСверху }
    }

    private var размер: CGFloat { уровень == .вложенное ? 14 : 15 }

    private var насыщенность: Font.Weight {
        switch уровень {
        case .всё:       return .heavy
        case .регион:    return .bold
        case .вложенное: return .regular
        }
    }

    private var цветТекста: Color {
        выбрана || уровень == .всё ? Theme.зелёный2 : Theme.текст
    }

    /// Выбранная — черта 3 pt акцентом (inset 3px 0 0); вложенная — тонкая зелёная черта отступа (.mk-city-sub::before).
    @ViewBuilder
    private var черта: some View {
        if выбрана {
            Rectangle()
                .fill(Theme.зелёный2)
                .frame(width: 3)
        } else if уровень == .вложенное {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(Theme.зелёный2.opacity(0.24))
                .frame(width: 2)
                .padding(.leading, 22)
        }
    }

    /// Линия над строкой «По всей стране», города и области (border-top 1px --mk-line).
    @ViewBuilder
    private var линияСверху: some View {
        if уровень != .вложенное {
            Rectangle()
                .fill(Theme.линия)
                .frame(height: 1)
        }
    }
}

/// Кнопка раскрытия (.mk-city-plus): квадрат 36 pt со стрелкой вниз, раскрытая — стрелка вверх акцентом.
private struct КнопкаРаскрытия: View {
    let раскрыта: Bool
    let подпись: String
    let действие: () -> Void

    var body: some View {
        Button(action: действие) {
            Image(systemName: "chevron.down")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(раскрыта ? Theme.зелёный2 : Theme.текст)
                .rotationEffect(.degrees(раскрыта ? 180 : 0))
                .frame(width: 36, height: 36)
                .background(раскрыта ? Theme.оттенокАкцента : КраскиГео.фонЧипа,
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(подпись)
        .accessibilityValue(GeoText.т(раскрыта ? "expanded" : "collapsed"))
    }
}

/// Заголовок группы («Крупные города», «Регион») — мелко, заглавными, серым, как подзаголовки сайта (.mk-msub).
private struct ЗаголовокГео: View {
    let текст: String

    var body: some View {
        Text(текст)
            .font(.system(size: 12, weight: .heavy))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(Theme.текстВторой)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 6)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Ничего не нашлось (.mk-geo-none).
private struct НичегоНеНашли: View {
    var body: some View {
        VStack(spacing: 4) {
            Text(GeoText.т("none"))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.текст)
            Text(GeoText.т("none_hint"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 14)
        .accessibilityElement(children: .combine)
    }
}
