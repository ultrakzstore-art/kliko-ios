import SwiftUI
import UIKit
import Photos

/**
 «ПОМЕСТИТСЯ ЛИ?» — ЛИСТЫ: «УКАЖИТЕ РАЗМЕРЫ» И СНИМОК (владелец 13.10.2026: «нужнее охват всего»).

 Лист размеров — три поля в сантиметрах (ширина, высота, глубина) с цифровой клавиатурой и «Далее» над ней. Что нашли
 в объявлении (РазборГабаритов) — уже в полях, и сверху сказано, откуда: из характеристик, из описания (с кусочком
 текста), примерно по диагонали или «не нашли»; под этим — «Размеры есть в описании или у продавца». Значение вне
 0,5–1000 см — поле краснеет и подсказывает пределы; «Готово» — когда все три в порядке. Запятая и точка, арабские
 цифры — всё понимается.

 Размеров в объявлении нет, нашлись не все три или они — прикидка по диагонали (владелец 16.10.2026) — под полями блок
 «Готовые размеры» (БлокГотовыхРазмеров, FitBoxTemplates.swift): вид вещи по разделу и названию, сетка образцов,
 «Другая вещь ›». Касание образца — числа перекатываются в поля, клавиатура убирается, подпись под полями — «Типичные
 размеры для …»; ручная правка поля снимает выбор. Тогда клавиатура сама не выезжает: сначала видно, из чего выбрать.
 «Готово» отдаёт с размерами пометку «примерно» — образец или нетронутая прикидка (окно пишет «Размер примерный»).

 Лист снимка — кадр с коробкой и подписями, «Сохранить в Фото» (доступ только на добавление) и «Поделиться»
 (системный лист); «Вернуться к камере» — закрыть.
 */
struct ЛистРазмеровГабаритов: View {
    let найдено: НайденныеГабариты
    /// Размеры и пометка «примерно»: имя образца каталога («Ноутбук 15,6″»), пусто — примерно без имени (нетронутая
    /// прикидка по диагонали или типичный размер продавца), nil — со слов продавца или введены руками.
    let готово: (ГабаритыВещи, String?) -> Void
    let отмена: () -> Void
    @State private var ширина: String
    @State private var высота: String
    @State private var глубина: String
    /// «Готовые размеры»: вид вещи (угадан или выбран) и ключ выбранного образца; ручная правка поля снимает выбор.
    @State private var вид: ВидРазмеров?
    @State private var образец: String?
    /// Открыт список «Другая вещь».
    @State private var выборВида = false
    /// Блок «Готовые размеры» показан (размеров в объявлении нет, не все или прикидка), виды каталога и виды раздела
    /// для кнопок, когда вид не поняли.
    private let готовыеНужны: Bool
    private let видыКаталога: [ВидРазмеров]
    private let кандидатыВидов: [ВидРазмеров]
    @FocusState private var поле: Поле?
    @Environment(\.dynamicTypeSize) private var размерТекста

    enum Поле: Hashable {
        case ширина
        case высота
        case глубина
    }

    /// раздел и название — объявления: по ним «Готовые размеры» угадывают вид вещи.
    init(найдено: НайденныеГабариты, текущие: ГабаритыВещи?, раздел: String? = nil, название: String = "",
         готово: @escaping (ГабаритыВещи, String?) -> Void, отмена: @escaping () -> Void) {
        self.найдено = найдено
        self.готово = готово
        self.отмена = отмена
        var ш = Self.строка(текущие?.ширина ?? найдено.ширина)
        var в = Self.строка(текущие?.высота ?? найдено.высота)
        var г = Self.строка(текущие?.глубина ?? найдено.глубина)
        /* «Готовые размеры»: вид вещи — сам. Полей нечем было заполнить (или там прикидка по диагонали), а в названии
           есть диагональ или размер образца — он сразу в полях и выбран; иначе выбран образец, с которым поля
           совпали. */
        let нужны = ГотовыеРазмеры.нужны(найдено)
        let виды = нужны ? ГотовыеРазмеры.виды : []
        let угаданный = ГотовыеРазмеры.вид(раздел: раздел, название: название, виды: виды)
        var выбранный: String? = nil
        if let угаданный {
            if текущие == nil, найдено.пусто || ГотовыеРазмеры.прикидка(найдено),
               let свой = ГотовыеРазмеры.образец(угаданный, название: название, найдено: найдено) {
                ш = String(свой.ширина)
                в = String(свой.высота)
                г = String(свой.глубина)
                выбранный = свой.ключ
            } else {
                выбранный = ГотовыеРазмеры.совпавший(угаданный, ширина: Self.значение(ш), высота: Self.значение(в),
                                                     глубина: Self.значение(г))?.ключ
            }
        }
        готовыеНужны = нужны && !виды.isEmpty
        видыКаталога = виды
        кандидатыВидов = нужны ? ГотовыеРазмеры.кандидаты(раздел: раздел, виды: виды) : []
        _ширина = State(initialValue: ш)
        _высота = State(initialValue: в)
        _глубина = State(initialValue: г)
        _вид = State(initialValue: угаданный)
        _образец = State(initialValue: выбранный)
    }

    private func т(_ ключ: String) -> String { ГабаритыText.т(ключ) }

    private static func строка(_ значение: Double?) -> String {
        значение.map { ГабаритыВещи.число($0) } ?? ""
    }

    /// Текст поля → сантиметры: запятая или точка, арабские цифры; вне пределов — nil.
    static func значение(_ текст: String) -> Double? {
        var чисто = ""
        for знак in текст.unicodeScalars {
            switch знак.value {
            case 0x0660...0x0669:
                чисто.append(String(знак.value - 0x0660))
            case 0x06F0...0x06F9:
                чисто.append(String(знак.value - 0x06F0))
            case 0x002C, 0x066B:
                чисто.append(".")
            case 0x0030...0x0039, 0x002E:
                чисто.unicodeScalars.append(знак)
            default:
                continue
            }
        }
        guard let число = Double(чисто), ГабаритыВещи.пределы.contains(число) else { return nil }
        return число
    }

    private var итог: ГабаритыВещи? {
        guard let ш = Self.значение(ширина), let в = Self.значение(высота), let г = Self.значение(глубина) else {
            return nil
        }
        return ГабаритыВещи(ширина: ш, высота: в, глубина: г)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    шапка
                    источник
                    VStack(spacing: 10) {
                        строкаПоля(.ширина, подпись: т("fb_w"), значок: "arrow.left.and.right", текст: $ширина)
                        строкаПоля(.высота, подпись: т("fb_h"), значок: "arrow.up.and.down", текст: $высота)
                        строкаПоля(.глубина, подпись: т("fb_d"), значок: "arrow.up.left.and.arrow.down.right",
                                   текст: $глубина)
                    }
                    /* Поля пусты, а ниже «Готовые размеры» — «со слов продавца» не к месту; без неё на iPhone SE первый
                       ряд образцов виден сразу. */
                    if !(готовыеНужны && ширина.isEmpty && высота.isEmpty && глубина.isEmpty) {
                        заметка
                    }
                    if готовыеНужны {
                        БлокГотовыхРазмеров(вид: вид, кандидаты: кандидатыВидов, выбранный: образец,
                                            выбрать: { применить($0) }, выбратьВид: { выбратьВид($0) }) {
                            поле = nil
                            выборВида = true
                        }
                    }
                }
                .padding(20)
                /* iPad: лист шире телефона — поля и сетка не растягиваются во всю ширину. */
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: ширина) { _, _ in сверитьОбразец() }
            .onChange(of: высота) { _, _ in сверитьОбразец() }
            .onChange(of: глубина) { _, _ in сверитьОбразец() }
            .navigationDestination(isPresented: $выборВида) {
                ВыборВидаГабаритов(виды: видыКаталога, выбран: вид?.ключ) { новый in
                    выбратьВид(новый)
                    выборВида = false
                }
            }
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .navigationTitle(т("fb_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(т("fb_cancel"), action: отмена)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(т("fb_done"), action: сохранить)
                        .fontWeight(.bold)
                        .disabled(итог == nil)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    /* Только у своих полей: у поиска «Другая вещь» клавиатура своя, «Далее» там не к месту. Признак —
                       открыт ли список, а не фокус: фокус при касании поля приходит позже, и панель собралась бы пустой
                       (у цифровой клавиатуры нет своей «Готово»). */
                    if !выборВида {
                        Spacer()
                        Button(поле == .глубина ? т("fb_done") : т("fb_next"), action: дальше)
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            /* Первое пустое поле — сразу под палец (когда лист доедет). Есть «Готовые размеры» — клавиатура сама не
               выезжает: сначала видно, из чего выбрать. */
            guard !готовыеНужны, let пустое = первоеПустое else { return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                поле = пустое
            }
        }
    }

    private var первоеПустое: Поле? {
        if Self.значение(ширина) == nil { return .ширина }
        if Self.значение(высота) == nil { return .высота }
        if Self.значение(глубина) == nil { return .глубина }
        return nil
    }

    private func сохранить() {
        guard let итог else { return }
        ОткликСайта.успех()
        готово(итог, пометка(итог))
    }

    /// Пометка «примерно» для окна: выбран образец — его имя («Ноутбук 15,6″»); прикидка по диагонали или типичный
    /// размер продавца, а поля не трогали — пусто (примерно без имени); иначе nil — со слов продавца или руками.
    private func пометка(_ итог: ГабаритыВещи) -> String? {
        if let текущий = текущийОбразец {
            return ГотовыеРазмеры.подпись(текущий.образец, вида: текущий.вид)
        }
        switch найдено.источник {
        case .диагональ, .образец:
            return итог == найдено.полные ? "" : nil
        case .подача, .характеристики, .описание, .нет:
            return nil
        }
    }

    /// Выбранный образец с его видом; nil — не выбран. Ищется и среди других видов: после «Другая вещь» в полях могут
    /// остаться числа образца прежнего вида (ключи встроенных образцов — sz_<вид>_<n> — не повторяются).
    private var текущийОбразец: (образец: ОбразецРазмеров, вид: ВидРазмеров)? {
        guard let ключ = образец else { return nil }
        let где: [ВидРазмеров] = (вид.map { [$0] } ?? []) + видыКаталога
        for свой in где {
            if let о = свой.образцы.first(where: { $0.ключ == ключ }) { return (образец: о, вид: свой) }
        }
        return nil
    }

    /// Касание образца: Ш×В×Г в поля (числа перекатываются), клавиатура убирается, VoiceOver слышит, что подставили.
    private func применить(_ о: ОбразецРазмеров) {
        поле = nil
        ОткликСайта.выбор()
        withAnimation(ДвижениеСайта.смена) {
            ширина = String(о.ширина)
            высота = String(о.высота)
            глубина = String(о.глубина)
            образец = о.ключ
        }
        if let вид {
            UIAccessibility.post(notification: .announcement,
                                 argument: ГотовыеРазмерыText.т("fbt_filled", ГотовыеРазмеры.озвучка(о, вида: вид)))
        }
    }

    /// Выбран вид («Другая вещь» или кнопка вида раздела) — его образцы; поля остаются, выбран образец, с которым они
    /// совпали; ни один не совпал — прежний образец остаётся (в полях всё ещё его числа, и подпись честно о нём).
    private func выбратьВид(_ новый: ВидРазмеров) {
        поле = nil
        withAnimation(ДвижениеСайта.смена) {
            вид = новый
            образец = ГотовыеРазмеры.совпавший(новый, ширина: Self.значение(ширина), высота: Self.значение(высота),
                                               глубина: Self.значение(глубина))?.ключ ?? образец
        }
    }

    /// Поле поправили руками, и оно разошлось с образцом — выбор снимается, под полями — снова «со слов продавца».
    private func сверитьОбразец() {
        guard let текущий = текущийОбразец else { return }
        let о = текущий.образец
        let совпал = Self.значение(ширина) == Double(о.ширина) && Self.значение(высота) == Double(о.высота)
            && Self.значение(глубина) == Double(о.глубина)
        if !совпал {
            withAnimation(ДвижениеСайта.выбор) { образец = nil }
        }
    }

    private func дальше() {
        switch поле {
        case .some(.ширина):
            поле = .высота
        case .some(.высота):
            поле = .глубина
        case .some(.глубина), .none:
            поле = nil
            if итог != nil { сохранить() }
        }
    }

    // MARK: Части

    private var шапка: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "cube.transparent")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.акцент)
                .frame(width: 48, height: 48)
                .background(Theme.оттенокАкцента,
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(т("fb_sizes_title"))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.текст)
                    .accessibilityAddTraits(.isHeader)
                Text(т("fb_sizes_sub"))
                    .font(.subheadline)
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Под полями: выбран образец — честное «Типичные размеры для «Ноутбук 15,6″» — у конкретной модели бывает на
    /// 1–2 см иначе»; нет — «Размеры — со слов продавца…». Смена — плавно (касание образца и правка поля идут с
    /// анимацией).
    private var заметка: some View {
        let текст = текущийОбразец.map { свой in
            ГотовыеРазмерыText.т("fbt_note", ГотовыеРазмеры.подпись(свой.образец, вида: свой.вид))
        } ?? т("fb_note")
        /* ZStack: прежняя и новая строки на время смены лежат друг на друге, а не толкают сетку вниз. */
        return ZStack(alignment: .topLeading) {
            Text(текст)
                .font(.footnote)
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(текст)
                .transition(.opacity)
        }
    }

    private var текстИсточника: String {
        switch найдено.источник {
        case .подача:
            return найдено.полные != nil ? т("fb_src_form") : т("fb_src_partial")
        case .характеристики:
            return найдено.полные != nil ? т("fb_src_specs") : т("fb_src_partial")
        case .образец:
            return найдено.полные != nil ? т("fb_src_tpl") : т("fb_src_partial")
        case .описание:
            return найдено.полные != nil ? т("fb_src_desc") : т("fb_src_partial")
        case .диагональ(let дюймы):
            return ГабаритыText.т("fb_src_diag", ГабаритыВещи.число(дюймы))
        case .нет:
            return т("fb_src_none")
        }
    }

    private var значокИсточника: String {
        switch найдено.источник {
        case .подача: return "checkmark.seal.fill"
        case .характеристики: return "checkmark.seal"
        case .образец: return "ruler"
        case .описание: return "text.quote"
        case .диагональ: return "tv"
        case .нет: return "questionmark.circle"
        }
    }

    private var цитата: String? {
        if case .описание(let кусок) = найдено.источник, !кусок.isEmpty { return кусок }
        return nil
    }

    private var источник: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: значокИсточника)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.акцент)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(текстИсточника)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.текст)
                    .fixedSize(horizontal: false, vertical: true)
                if let цитата {
                    Text("«" + цитата + "»")
                        .font(.footnote.italic())
                        .foregroundStyle(Theme.текстВторой)
                        .lineLimit(4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.мята, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func строкаПоля(_ своё: Поле, подпись: String, значок: String, текст: Binding<String>) -> some View {
        let плохо = !текст.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty
            && Self.значение(текст.wrappedValue) == nil
        let выбрано = поле == своё
        /* Не в фокусе и не пусто — число рисует Text поверх поля (само поле прозрачно): касание образца перекатывает
           цифры (numericText); в фокусе — обычное поле с кареткой. Text поверх лежит всегда, пока поле не в фокусе, и у
           пустого (пустой Text места не занимает, «0» не закрывает): иначе первое касание образца вставило бы его
           заново — проявлением, без перекатки. */
        let поверх = !выбрано && !текст.wrappedValue.isEmpty
        let раскладка = размерТекста.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        return VStack(alignment: .leading, spacing: 4) {
            раскладка {
                HStack(spacing: 12) {
                    Image(systemName: значок)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.акцент)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    Text(подпись)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.текст)
                }
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    TextField("0", text: текст)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(поверх ? Color.clear : Theme.текст)
                        .focused($поле, equals: своё)
                        .frame(minWidth: 64, maxWidth: 140)
                        .overlay(alignment: .trailing) {
                            if !выбрано {
                                Text(текст.wrappedValue)
                                    .font(.title3.weight(.bold).monospacedDigit())
                                    .foregroundStyle(Theme.текст)
                                    .lineLimit(1)
                                    .contentTransition(.numericText())
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                            }
                        }
                        .accessibilityLabel(подпись + ", " + т("fb_in_cm"))
                    Text(т("fb_cm"))
                        .font(.body)
                        .foregroundStyle(Theme.текстВторой)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 56)
            .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                    .strokeBorder(плохо ? Theme.ценаСкидка : (выбрано ? Theme.акцент : Theme.линия),
                                  lineWidth: выбрано || плохо ? 1.5 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .onTapGesture { поле = своё }
            if плохо {
                Text(т("fb_bad"))
                    .font(.footnote)
                    .foregroundStyle(Theme.скидкаТекст)
            }
        }
    }
}

// MARK: - Снимок

struct ЛистСнимкаГабаритов: View {
    let снимок: СнимокГабаритов
    let габариты: ГабаритыВещи?
    let закрыть: () -> Void
    @State private var сохраняем = false
    @State private var итог: String? = nil
    @State private var итогХорошо = false

    init(снимок: СнимокГабаритов, габариты: ГабаритыВещи?, закрыть: @escaping () -> Void) {
        self.снимок = снимок
        self.габариты = габариты
        self.закрыть = закрыть
    }

    private func т(_ ключ: String) -> String { ГабаритыText.т(ключ) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Image(uiImage: снимок.картинка)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
                        .accessibilityLabel(снимок.озвучка
                                            ?? габариты.map { ГабаритыText.т("fb_shot_img", $0.озвучка) }
                                            ?? т("fb_shot_title"))
                    кнопки
                    if let итог {
                        Label(итог, systemImage: итогХорошо ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(итогХорошо ? Theme.акцент : Theme.скидкаТекст)
                            .multilineTextAlignment(.center)
                            .transition(.opacity)
                    }
                }
                .padding(20)
                .animation(ДвижениеСайта.смена, value: итог)
            }
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .navigationTitle(т("fb_shot_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(т("fb_back"), action: закрыть)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var кнопки: some View {
        let картинка = Image(uiImage: снимок.картинка)
        return VStack(spacing: 10) {
            Button(action: сохранить) {
                HStack(spacing: 8) {
                    if сохраняем {
                        SiteSpinner(размер: 18, толщина: 2.5, дорожка: Color.white.opacity(0.3), верх: Color.white,
                                    стоит: ДвижениеСайта.тихо)
                    } else {
                        Image(systemName: "square.and.arrow.down")
                            .accessibilityHidden(true)
                    }
                    Text(т("fb_save"))
                }
                .font(.body.weight(.bold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Theme.зелёный, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            }
            .buttonStyle(НажатиеКнопкиФото(сжатие: 0.97))
            .disabled(сохраняем)
            ShareLink(item: картинка, preview: SharePreview(т("fb_share_title"), image: картинка)) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                        .accessibilityHidden(true)
                    Text(т("fb_share"))
                }
                .font(.body.weight(.bold))
                .foregroundStyle(Theme.акцент)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Theme.оттенокАкцента,
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                        .strokeBorder(Theme.панельКромка, lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            }
            .buttonStyle(НажатиеКнопкиФото(сжатие: 0.97))
        }
    }

    private func сохранить() {
        guard !сохраняем else { return }
        сохраняем = true
        итог = nil
        let картинка = снимок.картинка
        Task {
            /* JPEG — не на главной нити: кадр во весь экран сжимается заметное время. */
            let данные = await Task.detached(priority: .userInitiated) {
                картинка.jpegData(compressionQuality: 0.92)
            }.value
            let ответ: СохранениеГабаритов.Итог
            if let данные {
                ответ = await СохранениеГабаритов.вФото(данные)
            } else {
                ответ = .сбой
            }
            сохраняем = false
            switch ответ {
            case .готово:
                итогХорошо = true
                итог = т("fb_saved")
                ОткликСайта.успех()
            case .нетДоступа:
                итогХорошо = false
                итог = т("fb_save_denied")
                ОткликСайта.предупреждение()
            case .сбой:
                итогХорошо = false
                итог = т("fb_save_fail")
                ОткликСайта.предупреждение()
            }
            if let итог { UIAccessibility.post(notification: .announcement, argument: итог) }
        }
    }
}

/// Снимок в Фото iPhone: доступ только на добавление (NSPhotoLibraryAddUsageDescription уже в Info.plist).
enum СохранениеГабаритов {
    enum Итог: Sendable {
        case готово
        case нетДоступа
        case сбой
    }

    static func вФото(_ данные: Data) async -> Итог {
        let доступ = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard доступ == .authorized || доступ == .limited else { return .нетДоступа }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: данные, options: nil)
            }
            return .готово
        } catch {
            return .сбой
        }
    }
}
