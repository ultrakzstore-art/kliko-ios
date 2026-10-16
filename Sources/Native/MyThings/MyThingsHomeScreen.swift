import SwiftUI
import UIKit

/**
 «МОЁ» — «МОЙ ДОМ» (пачка 16.10.2026 «мой дом, компьютер, гардероб и для вас»; владелец: «мой дом — что можно по
 дому?»; «стандарты: по ним изи точечно подбирать, что почём; шаблоны»; «удобно для глаз, ровная схема везде, мощная
 анимированная подача, летает на всех девайсах»).

 Экран сверху вниз (каскад ПоявлениеМоего, как у хаба):
   · шапка — кольцо прогресса дома (прогрессДома), сводка («160×200 · E27 ×6 · дверь 74 см») и следующий шаг;
   · «Первая минута — три касания» (docs/STANDARDS.md §8.2): кровать, лифт, цоколи — стандартами чипами; заполненное
     уходит, карточка — тоже;
   · «Пройдёт ли в дверь и лифт?» — вещь шаблоном или своими Ш×В×Г против пути в дом (MyThingsHomePass.swift);
   · комнаты (MyThingsHomeRooms.swift), проёмы, кровати, окна, ТВ на стене, свет (MyThingsHomeCards.swift), техника
     (MyThingsHomeAppliances.swift), стиль и цвета, купленное на Kliko для дома и «Добавить из моих покупок».
 Листы правки — MyThingsHomeSheets.swift. Всё — только на телефоне (МоёХранилище.обновитьДом), на сервер ничего не
 уходит; камера и фото — только по нажатию; цвета фото и текст наклейки читаются на телефоне.

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
            VStack(spacing: 14) {
                верх(запись)
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
        let дом = запись.дом
        ШапкаДомаМоего(прогресс: запись.прогрессДома, сводка: запись.сводкаДома)
            .появлениеМоего(0)
        if ПерваяМинутаДома.нужна(дом) {
            ПерваяМинутаДома(дом: дом, открыть: открыть)
                .появлениеМоего(1)
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
        }
        КарточкаПроходаДома(дом: дом, открыть: открыть)
            .появлениеМоего(2)
        КарточкаКомнатДома(дом: дом, открыть: открыть)
            .появлениеМоего(3)
        КарточкаПроёмовДома(дом: дом, открыть: открыть)
            .появлениеМоего(4)
    }

    @ViewBuilder
    private func низ(_ запись: ЗаписьМоего) -> some View {
        let дом = запись.дом
        let купленное = запись.вещиВ(.дом)
        КарточкаКроватейДома(дом: дом, открыть: открыть)
            .появлениеМоего(5)
        КарточкаОконДома(дом: дом, открыть: открыть)
            .появлениеМоего(6)
        КарточкаЭкрановДома(дом: дом, устройства: запись.экраны, открыть: открыть)
            .появлениеМоего(7)
        КарточкаСветаДома(дом: дом)
            .появлениеМоего(8)
        КарточкаТехникиДома(дом: дом, открыть: открыть)
            .появлениеМоего(9)
        КарточкаСтиляДома(дом: дом)
            .появлениеМоего(10)
        if !купленное.isEmpty || Config.покупкиВМоё {
            КарточкаКупленногоДома(вещи: купленное, дом: дом)
                .появлениеМоего(11)
        }
        приватность
            .появлениеМоего(12)
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

// MARK: - Первая минута

/**
 «Первая минута — три касания» (docs/STANDARDS.md §8.2): кровать — частые спальные места; лифт — «Лифта нет», «1-й
 этаж или свой дом», типовые лифты (EN 81-70 и «советский ≈», «грузовой ≈») и «Свой замер»; лампы — частые цоколи
 картинками (+1 лампа). Заполненная строка уходит, все три — уходит карточка.
 */
struct ПерваяМинутаДома: View {
    let дом: ДомМоего
    let открыть: (ЛистДомаМоего) -> Void

    init(дом: ДомМоего, открыть: @escaping (ЛистДомаМоего) -> Void) {
        self.дом = дом
        self.открыть = открыть
    }

    private func т(_ ключ: String) -> String { МойДомText.т(ключ) }

    static func естьКровать(_ д: ДомМоего) -> Bool { д.кровати.contains(where: \.заполнена) }
    static func естьЛифт(_ д: ДомМоего) -> Bool { д.лифтаНет || д.проёмы.contains { $0.вид == .лифт && $0.заполнен } }
    static func естьЛампы(_ д: ДомМоего) -> Bool { !д.лампы.isEmpty }

    static func нужна(_ д: ДомМоего) -> Bool { !естьКровать(д) || !естьЛифт(д) || !естьЛампы(д) }

    private var готово: Int {
        [Self.естьКровать(дом), Self.естьЛифт(дом), Self.естьЛампы(дом)].filter { $0 }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ЗаголовокМоего(т("mh_first"), значок: "bolt.fill")
                Spacer(minLength: 8)
                Text(String(готово) + "/3")
                    .font(.caption.weight(.heavy).monospacedDigit())
                    .foregroundStyle(РазделМоего.дом.цвет)
                    .contentTransition(.numericText(value: Double(готово)))
                    .accessibilityLabel(String(format: т("mh_first_a11y"), String(готово)))
            }
            Text(т("mh_first_sub"))
                .font(.footnote)
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            if !Self.естьКровать(дом) {
                строкаКровати
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }
            if !Self.естьЛифт(дом) {
                строкаЛифта
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }
            if !Self.естьЛампы(дом) {
                строкаЛамп
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        .карточкаМоего()
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(РазделМоего.дом.цвет.opacity(0.35), lineWidth: 1.5)
        }
    }

    private var строкаКровати: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(т("mh_first_bed"), systemImage: "bed.double")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.текст)
            ПотокЧипов(зазор: 8) {
                ForEach(КаталогСтандартов.частыеСпальныеМеста, id: \.self) { место in
                    ЧипМоего(КаталогСтандартов.показ(место), выбран: false) { кровать(место) }
                }
                ЧипМоего(т("mh_bed_other"), выбран: false, значок: "slider.horizontal.3") {
                    ОткликСайта.выбор()
                    открыть(.кровать(КроватьМоего(), новая: true))
                }
            }
        }
    }

    private var строкаЛифта: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(т("mh_first_lift"), systemImage: "arrow.up.arrow.down.square")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.текст)
            ПотокЧипов(зазор: 8) {
                ЧипМоего(т("mh_no_lift"), выбран: false, значок: "xmark") { безЛифта(этаж: nil) }
                ЧипМоего(т("mh_ground"), выбран: false, значок: "house") { безЛифта(этаж: 0) }
                ForEach(КаталогСтандартов.лифты) { лифт in
                    ЧипМоего(т("mh_lift_short_" + лифт.id), выбран: false) { добавитьЛифт(лифт) }
                }
                ЧипМоего(т("mh_lift_own_short"), выбран: false, значок: "ruler") {
                    ОткликСайта.выбор()
                    открыть(.проём(ПроёмМоего(вид: .лифт), новый: true))
                }
            }
        }
    }

    private var строкаЛамп: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(т("mh_first_lamps"), systemImage: "lightbulb")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.текст)
            ПотокЧипов(зазор: 8) {
                ForEach(КаталогСтандартов.цоколи.filter(\.частый), id: \.id) { ц in
                    ЧипЦоколяДома(код: ц.id) { лампа(ц.id) }
                }
            }
        }
    }

    // MARK: Действия

    private func кровать(_ место: String) {
        ОткликСайта.успех()
        МоёХранилище.shared.обновитьДом { д in
            if let i = д.кровати.firstIndex(where: { $0.место == nil }) {
                д.кровати[i].место = место
            } else if д.кровати.count < ДомМоего.пределКроватей {
                д.кровати.append(КроватьМоего(место: место))
            }
        }
    }

    private func безЛифта(этаж: Int?) {
        ОткликСайта.успех()
        МоёХранилище.shared.обновитьДом { д in
            д.лифтаНет = true
            if let этаж { д.этаж = этаж }
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

    private func лампа(_ код: String) {
        ОткликСайта.успех()
        МоёХранилище.shared.обновитьДом { д in
            if let i = д.лампы.firstIndex(where: { $0.цоколь == код && $0.комната == nil }) {
                д.лампы[i].сколько = min(ЛампыМоего.пределыСколько.upperBound, д.лампы[i].сколько + 1)
            } else if д.лампы.count < ДомМоего.пределЛамп {
                д.лампы.append(ЛампыМоего(цоколь: код, сколько: 1))
            }
        }
    }
}

/// Чип цоколя с картинкой: «[рисунок] E27».
struct ЧипЦоколяДома: View {
    let код: String
    let действие: () -> Void

    init(код: String, действие: @escaping () -> Void) {
        self.код = код
        self.действие = действие
    }

    var body: some View {
        Button(action: действие) {
            HStack(spacing: 6) {
                РисунокЦоколяДома(код: код, размер: 24)
                Text(код)
                    .font(.subheadline.weight(.bold))
            }
            .foregroundStyle(Theme.акцент)
            .padding(.leading, 6)
            .padding(.trailing, 12)
            .frame(minHeight: 40)
            .background(Theme.оттенокАкцента, in: Capsule())
            .overlay { Capsule().strokeBorder(Theme.рамкаПункта, lineWidth: 1) }
            .contentShape(Capsule())
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.95))
        .accessibilityLabel(код + ", " + (КаталогСтандартов.цоколь(код)?.пояснение ?? ""))
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
        .accessibilityAction(named: т("mh_bought_remove")) { убрать(вещь.id) }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func убрать(_ id: UUID) {
        ОткликСайта.выбор()
        withAnimation(ДвижениеСайта.вставкаСписка) { МоёХранилище.shared.удалитьВещь(id) }
    }
}
