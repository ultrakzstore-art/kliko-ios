import SwiftUI
import UIKit

/**
 «ИЩУ» ИЗ «МОЕГО» (пачка 83, владелец 17.10.2026: «чтобы этот самый механизм работал на пользу юзеру от продавца к
 покупателю и наоборот»; docs/SERVER_NEW_FOR_MINE.md §16.3.8 — «Ищу» до сервера).

 Кнопка «Ищу шины 205/55 R16» в разделах «Моего», где есть значения: машина (размер шин), дом (кровать — матрас и бельё,
 свет — лампы по цоколю, ТВ на стене — кронштейн по VESA), гардероб (обувь и одежда своего размера), компьютер (память,
 SSD под слот M.2). Нажатие — лист: что именно (если вариантов несколько), «до какой цены», состояние, ровно то название
 поиска, которое потом будет в «Сохранённых поисках», и «Сохранить поиск».

 Это существующий сохранённый поиск (SavedSearchStore.добавить, SavedSearch/SubsSync.swift): keyword — значение стандарта,
 как его пишут в названиях («205/55 R16», «160x200», «E27», «400x400», «DDR4 SO-DIMM»), раздел, pmax, cond — ровно поля
 subs.php?action=add. У гостя поиск живёт на телефоне и проверяется в фоне (одно локальное уведомление); у вошедшего —
 и подпиской аккаунта (Config.подпискиССайтом), как колокольчик ленты: человек видит этот текст в листе до сохранения.
 Остальное «Моё» никуда не уходит; значения fit_* в subs.php не шлются. Новых адресов нет: публичный запрос wanted_put
 (§16.3.2) — только за рубильником wanted_std, которого в этой сборке нет (ключа в белом списке RemoteSettings нет), —
 здесь его не зовём.

 Слова поиска — без слов языка («матрас», «лампа»): названия на площадке пишут по-русски, а лист бывает на kk/en/ar;
 значение стандарта одно на всех. Размер одежды — только числом системы сайта из двух и больше знаков («42», «48»):
 буквы («M») нашли бы что угодно — такого варианта нет.
 */

extension Config {
    /// «Ищу» в разделах «Моего» (сохранённый поиск со стандартом). false — кнопок «Ищу» нет.
    static let ищуИзМоего = true
}

// MARK: - Что искать

/// Одна вещь: подпись после «Ищу» («шины 205/55 R16»), раздел сайта и слово поиска (keyword subs.php).
struct ВариантИщуМоего: Hashable, Identifiable, Sendable {
    let подпись: String
    let раздел: String
    let слово: String

    init(подпись: String, раздел: String, слово: String) {
        self.подпись = подпись
        self.раздел = раздел
        self.слово = слово.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var id: String { раздел + "|" + слово }
}

/// Варианты одной кнопки «Ищу» (1–4, без повторов); первый — главный: его подпись на кнопке.
struct ЗапросИщуМоего: Hashable, Identifiable, Sendable {
    let варианты: [ВариантИщуМоего]
    let первый: ВариантИщуМоего

    init?(_ все: [ВариантИщуМоего]) {
        var видели = Set<String>()
        let чистые: [ВариантИщуМоего] = все.filter { (в: ВариантИщуМоего) -> Bool in
            !в.слово.isEmpty && !в.раздел.isEmpty && видели.insert(в.id).inserted
        }
        guard let главный = чистые.first else { return nil }
        первый = главный
        варианты = Array(чистые.prefix(4))
    }

    var id: String {
        let ключи: [String] = варианты.map { (в: ВариантИщуМоего) -> String in в.id }
        return ключи.joined(separator: ",")
    }
}

// MARK: - Сборщики из «Моего»

@MainActor
enum ИщуМоего {
    /// «Ищу» есть, когда он включён и есть «Моё» и сохранённые поиски.
    static var доступно: Bool { Config.ищуИзМоего && Config.моё && Config.сохранённыеПоиски }

    private static func ф(_ ключ: String, _ аргумент: String) -> String { ИщуМоегоText.ф(ключ, аргумент) }

    /// «Ищу шины 205/55 R16».
    static func заголовок(_ вариант: ВариантИщуМоего) -> String { ф("iw_head", вариант.подпись) }

    /// Лист «Ищу» поверх того, что на экране (половина высоты, тянется во всю).
    static func открыть(_ запрос: ЗапросИщуМоего) {
        guard доступно else { return }
        ПоверхВсего.показать(большой: false) { закрыть in
            ЛистИщуМоего(запрос: запрос, закрыть: закрыть)
        }
    }

    /// Машина: штатный размер шин.
    static func машина(_ м: МашинаМоего) -> ЗапросИщуМоего? {
        guard доступно, let ш = м.посадка?.шины.first, ш.годный else { return nil }
        let размер: String = ш.подпись
        let шины = ВариантИщуМоего(подпись: ф("iw_tyres", размер), раздел: "tires-wheels", слово: размер)
        return ЗапросИщуМоего([шины])
    }

    /// Раздел дома: кровать — матрас и бельё её размера (до двух размеров), свет — лампы по цоколям (частые первыми, до
    /// трёх), ТВ на стене — кронштейн по VESA. У прочих разделов «Ищу» нет.
    static func дом(_ раздел: РазделДомаМоего, _ д: ДомМоего) -> ЗапросИщуМоего? {
        guard доступно, Config.мойДом else { return nil }
        var варианты: [ВариантИщуМоего] = []
        switch раздел {
        case .кровати:
            var места: [String] = []
            for кровать in д.кровати {
                if let место = кровать.место, !места.contains(место) { места.append(место) }
            }
            for место in места.prefix(2) {
                let показ: String = КаталогСтандартов.показ(место)
                варианты.append(ВариантИщуМоего(подпись: ф("iw_mattress", показ), раздел: "beds", слово: место))
                варианты.append(ВариантИщуМоего(подпись: ф("iw_bedding", показ), раздел: "bedding", слово: место))
            }
        case .свет:
            let счёт: [String: Int] = д.цоколи
            let коды: [String] = счёт.keys.sorted { (а: String, б: String) -> Bool in
                let на: Int = счёт[а] ?? 0
                let нб: Int = счёт[б] ?? 0
                if на != нб { return на > нб }
                return а < б
            }
            for код in коды.prefix(3) {
                варианты.append(ВариантИщуМоего(подпись: ф("iw_lamps", код), раздел: "lighting", слово: код))
            }
        case .экраны:
            var шаблоны: [String] = []
            for экран in д.экраны {
                if let шаблон = экран.шаблонДляСверки?.шаблон, !шаблоны.contains(шаблон) { шаблоны.append(шаблон) }
            }
            for шаблон in шаблоны.prefix(2) {
                let показ: String = КаталогСтандартов.показ(шаблон)
                варианты.append(ВариантИщуМоего(подпись: ф("iw_mount", показ), раздел: "tv-audio", слово: шаблон))
            }
        case .комнаты, .проёмы, .окна, .техника, .стиль:
            return nil
        }
        return ЗапросИщуМоего(варианты)
    }

    /// Гардероб: свои размеры (с размерами вещей — ПодборДляВас.моёДляСверки) — обувь и одежда числом системы сайта.
    static func гардероб(_ запись: ЗаписьМоего) -> ЗапросИщуМоего? {
        guard доступно, Config.мойГардероб else { return nil }
        let моё: ЗаписьМоего = ПодборДляВас.моёДляСверки(запись)
        var варианты: [ВариантИщуМоего] = []
        for размер in моё.тело.размеры {
            if let вариант = вариантРазмера(размер) { варианты.append(вариант) }
        }
        return ЗапросИщуМоего(варианты)
    }

    private static func вариантРазмера(_ р: РазмерМоего) -> ВариантИщуМоего? {
        let ключ: String
        let раздел: String
        switch р.вид {
        case .обувьМ:
            ключ = "iw_shoes_m"
            раздел = "mens-shoes"
        case .обувьЖ:
            ключ = "iw_shoes_w"
            раздел = "womens-shoes"
        case .одеждаМ, .джинсыМ:
            ключ = "iw_clothes_m"
            раздел = "mens-clothing"
        case .одеждаЖ, .джинсыЖ:
            ключ = "iw_clothes_w"
            раздел = "womens-clothing"
        case .бельё, .кольцо, .шапка, .перчатки:
            return nil
        }
        guard let выбор = р.выбор() else { return nil }
        let вкладка: ВкладкаРазмеровОдежды = р.вид.вкладка
        let части: [ЧастьБиркиРазмера] = вкладка.части(выбор)
        guard let своя = части.first(where: { (ч: ЧастьБиркиРазмера) -> Bool in ч.код == вкладка.системаСайта })
        else { return nil }
        let значение: String = своя.значение.trimmingCharacters(in: .whitespaces)
        guard годитсяСловом(значение) else { return nil }
        let показ: String = РазмерыОдеждыText.показ(своя)
        return ВариантИщуМоего(подпись: ф(ключ, показ), раздел: раздел, слово: значение)
    }

    /// Размер словом поиска: число из 2–5 знаков («42», «48», «9.5»); буквы и «44–46» — нет.
    private static func годитсяСловом(_ значение: String) -> Bool {
        guard значение.count >= 2, значение.count <= 5 else { return false }
        return значение.allSatisfy { (с: Character) -> Bool in с.isASCII && (с.isNumber || с == ".") }
    }

    /// Компьютер: память его поколения и формы (не распаянная), SSD под первый слот M.2.
    static func компьютер(_ к: КомпьютерМоего) -> ЗапросИщуМоего? {
        guard доступно, Config.мойКомпьютер else { return nil }
        var варианты: [ВариантИщуМоего] = []
        let память = к.память
        if !память.всяРаспаяна, let поколение = память.поколение, let форма = память.форма, форма != "soldered" {
            let поля: [String: String] = [КлючСтандарта.поколение: поколение, КлючСтандарта.форма: форма]
            let набор = НаборСтандартов(значения: [СемьяСтандарта.память.rawValue: поля])
            let слово: String = РазборСтандартов.запрос(набор, .память)
            варианты.append(ВариантИщуМоего(подпись: ф("iw_ram", слово), раздел: "ram", слово: слово))
        }
        if let слот = к.слотыM2.first {
            let sata: Bool = слот.протокол == "sata"
            let слово: String = sata ? "M.2 SATA" : "NVMe"
            let подпись: String = sata ? "M.2 SATA" : "M.2 NVMe"
            варианты.append(ВариантИщуМоего(подпись: ф("iw_ssd", подпись), раздел: "ssd-hdd", слово: слово))
        }
        return ЗапросИщуМоего(варианты)
    }

    /// Название раздела на языке приложения без сети (как у сохранённых поисков): слова приложения, справочник поиска,
    /// снимок полосы разделов. Нет — nil (лист догрузит справочник сам).
    static func имяРаздела(_ ключ: String) -> String? {
        guard !ключ.isEmpty else { return nil }
        if РазделГлавной.своёНазвание.contains(ключ) { return DesignText.т("v_" + ключ) }
        if let имя = ЗагрузкаКаталогаПоиска.имя(ключ) { return имя }
        let строка: FeedSnapshot.Row? = FeedStore.разделыНаЗапуске.first { (р: FeedSnapshot.Row) -> Bool in р.k == ключ }
        return строка?.название
    }
}

// MARK: - Кнопка

/// «Ищу шины 205/55 R16» — малая кнопка с колокольчиком; открывает лист «Ищу».
struct КнопкаИщуМоего: View {
    let запрос: ЗапросИщуМоего

    init(_ запрос: ЗапросИщуМоего) {
        self.запрос = запрос
    }

    var body: some View {
        МалаяКнопкаАвтоподбора(заголовок: ИщуМоего.заголовок(запрос.первый), значок: "bell.badge") {
            ОткликСайта.выбор()
            ИщуМоего.открыть(запрос)
        }
        .accessibilityHint(ИщуМоегоText.т("iw_hint"))
    }
}

/// Кнопка «Ищу» отдельной карточкой с подписью — для экранов, где разделы — карточки (гардероб, компьютер).
struct БлокИщуМоего: View {
    let запрос: ЗапросИщуМоего

    init(_ запрос: ЗапросИщуМоего) {
        self.запрос = запрос
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            КнопкаИщуМоего(запрос)
            Text(ИщуМоегоText.т("iw_hint"))
                .font(.caption)
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
        }
        .карточкаМоего(поля: 14)
    }
}

// MARK: - Лист

/// Чем закончилось «Сохранить поиск».
enum ИтогИщуМоего: Equatable, Sendable {
    case сохранён
    case уже
    case полно
}

/**
 Лист «Ищу»: заголовок «Ищу шины 205/55 R16» и раздел, выбор варианта (если их несколько), «до какой цены» и
 состояние, название поиска ровно как в «Сохранённых поисках» и «Сохранить поиск». После — итог и «Посмотреть, что есть
 сейчас» (лента по этому же поиску). Смена варианта, цены или состояния снимает итог — можно сохранить и другой.
 */
struct ЛистИщуМоего: View {
    let запрос: ЗапросИщуМоего
    let закрыть: () -> Void
    @State private var выбран = 0
    @State private var цена = ""
    @State private var состояние = ""
    @State private var итог: ИтогИщуМоего? = nil
    @State private var имена: [String: String] = [:]

    init(запрос: ЗапросИщуМоего, закрыть: @escaping () -> Void) {
        self.запрос = запрос
        self.закрыть = закрыть
    }

    private func т(_ ключ: String) -> String { ИщуМоегоText.т(ключ) }

    private var вариант: ВариантИщуМоего {
        let последний: Int = запрос.варианты.count - 1
        let номер: Int = min(max(0, выбран), последний)
        return запрос.варианты[номер]
    }

    /// Поиск ленты: слово, раздел, «до» (только цифры) и состояние.
    private var искомое: ИскомоеЛенты {
        let цифры: String = цена.filter { (с: Character) -> Bool in с.isASCII && с.isNumber }
        let до: Int? = Int(String(цифры.prefix(10)))
        return ИскомоеЛенты(текст: вариант.слово, раздел: вариант.раздел, ценаДо: до, состояние: состояние)
    }

    private func имяРаздела(_ ключ: String) -> String? {
        имена[ключ] ?? ИщуМоего.имяРаздела(ключ)
    }

    /// Как поиск будет назван в «Сохранённых поисках» и в уведомлении.
    private var названиеПоиска: String {
        var запись = СохранённыйПоиск(искомое: искомое, названиеРаздела: имяРаздела(вариант.раздел))
        запись.подпись = ИщуМоего.заголовок(вариант)
        return запись.название
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    шапка
                    if запрос.варианты.count > 1 {
                        выбор
                    }
                    полеЦены
                    выборСостояния
                    пояснение
                    действия
                }
                .padding(16)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
                .animation(ДвижениеСайта.смена, value: итог)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(МоёText.т("my_close"), action: закрыть)
                }
            }
            .клавиатураМоего()
        }
        .tint(Theme.акцент)
        .task { await догрузитьИмена() }
        .onChange(of: выбран) { _, _ in итог = nil }
        .onChange(of: цена) { _, _ in итог = nil }
        .onChange(of: состояние) { _, _ in итог = nil }
    }

    private var шапка: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ИщуМоего.заголовок(вариант))
                .font(.title3.weight(.heavy))
                .foregroundStyle(Theme.текст)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
                .accessibilityAddTraits(.isHeader)
            if let имя = имяРаздела(вариант.раздел) {
                Text(имя)
                    .font(.subheadline)
                    .foregroundStyle(Theme.текстВторой)
                    .contentTransition(.opacity)
            }
        }
        .animation(ДвижениеСайта.смена, value: выбран)
    }

    private func подписьПоля(_ текст: String) -> some View {
        Text(текст)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Theme.текст)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(true)
    }

    private var выбор: some View {
        VStack(alignment: .leading, spacing: 8) {
            подписьПоля(т("iw_what"))
            ПотокЧипов(зазор: 8) {
                ForEach(Array(запрос.варианты.enumerated()), id: \.element.id) { номер, в in
                    ЧипМоего(в.подпись, выбран: номер == выбран) {
                        ОткликСайта.выбор()
                        выбран = номер
                    }
                }
            }
        }
    }

    private var полеЦены: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
        return VStack(alignment: .leading, spacing: 6) {
            подписьПоля(т("iw_upto"))
            TextField(т("iw_upto_ph"), text: $цена)
                .keyboardType(.numberPad)
                .font(.body.monospacedDigit())
                .foregroundStyle(Theme.текст)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Theme.поверхность, in: форма)
                .overlay { форма.strokeBorder(Theme.линия, lineWidth: 1) }
                .accessibilityLabel(т("iw_upto"))
        }
    }

    private var выборСостояния: some View {
        VStack(alignment: .leading, spacing: 6) {
            подписьПоля(т("iw_cond"))
            Picker(т("iw_cond"), selection: $состояние) {
                Text(т("iw_any")).tag("")
                Text(т("iw_new")).tag("new")
                Text(т("iw_used")).tag("used")
            }
            .pickerStyle(.segmented)
        }
    }

    private var пояснение: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(format: т("iw_how"), названиеПоиска))
                .font(.subheadline)
                .foregroundStyle(Theme.текст)
                .fixedSize(horizontal: false, vertical: true)
            Label {
                Text(т("iw_account"))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(Theme.акцент)
            }
            .font(.footnote)
            .foregroundStyle(Theme.текстВторой)
        }
    }

    @ViewBuilder
    private var действия: some View {
        if let готово = итог {
            VStack(alignment: .leading, spacing: 12) {
                Label(текстИтога(готово), systemImage: готово == .полно ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(готово == .полно ? Theme.оранжевый : Theme.зелёный2)
                    .fixedSize(horizontal: false, vertical: true)
                if готово != .полно {
                    ЗелёнаяКнопкаФото(заголовок: т("iw_look"), значок: "magnifyingglass", контурная: true) {
                        посмотреть()
                    }
                }
            }
            .transition(.opacity)
        } else {
            ЗелёнаяКнопкаФото(заголовок: т("iw_save"), значок: "bell.badge") {
                сохранить()
            }
            .transition(.opacity)
        }
    }

    private func текстИтога(_ готово: ИтогИщуМоего) -> String {
        switch готово {
        case .сохранён: return т("iw_saved")
        case .уже: return т("iw_already")
        case .полно: return String(format: SavedSearchText.т("full_msg"), SavedSearchStore.предел)
        }
    }

    /// Сохранить поиск — тот же путь, что колокольчик ленты: без точки отсчёта (первая проверка только запомнит
    /// выдачу и промолчит), первое сохранение спрашивает разрешение на уведомления.
    private func сохранить() {
        let что: ИскомоеЛенты = искомое
        let поиски = SavedSearchStore.shared
        if поиски.есть(что) {
            ОткликСайта.выбор()
            итог = .уже
            return
        }
        let имя: String? = имяРаздела(что.раздел)
        let подпись: String = ИщуМоего.заголовок(вариант)
        guard поиски.добавить(что, названиеРаздела: имя, видели: nil, подпись: подпись) else {
            ОткликСайта.предупреждение()
            итог = .полно
            return
        }
        ОткликСайта.успех()
        итог = .сохранён
        UIAccessibility.post(notification: .announcement, argument: т("iw_saved"))
        Task { @MainActor () -> Void in
            await ПроверкаПоисков.попроситьРазрешение()
        }
    }

    /// Лента по этому же поиску: лист закрывается, «Моё» окном поверх — тоже (ПереходыГардероба.послеОкон).
    private func посмотреть() {
        let что: ИскомоеЛенты = искомое
        закрыть()
        ПереходыГардероба.послеОкон {
            WebBridge.shared.открытьЭкран(.найти(что), запасной: nil)
        }
    }

    /// Названия разделов, которых нет ни в словах приложения, ни в справочнике на руках, — запасные (снимок сайта или
    /// справочник на языке приложения).
    private func догрузитьИмена() async {
        let ключи: [String] = запрос.варианты.map { (в: ВариантИщуМоего) -> String in в.раздел }
        let нет: [String] = ключи.filter { (ключ: String) -> Bool in ИщуМоего.имяРаздела(ключ) == nil }
        guard !нет.isEmpty else { return }
        let найдено: [String: String] = await ИменаРазделовСайта.запасные(нет)
        guard !найдено.isEmpty else { return }
        имена.merge(найдено) { (_: String, новое: String) -> String in новое }
    }
}
