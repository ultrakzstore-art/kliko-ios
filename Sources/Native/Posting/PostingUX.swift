import SwiftUI
import UIKit
import UniformTypeIdentifiers

/**
 ПОДАЧА — ПОНЯТНЕЕ И ПРОЩЕ (TestFlight 1.10, владелец: «редактирование и добавление — дизайн улучшить, более понятнее
 и проще»).

 Здесь — детали нового вида мастера; запросы, поля и проверки остались сайта (PostingModel, PostingSend):
   · строка ошибки под своим полем вместо всплывающих окон (ошибкиПолей модели);
   · фокус полей и панель «↑ ↓ Готово» над клавиатурой: поле само прокручивается в видимую часть;
   · выбор сегментом (2–4 коротких варианта), меню (средние списки), большое поле цены с «₸» и разрядами;
   · лист разделов: поиск по всему дереву, большие строки со значками и «хлебными крошками» вместо трёх списков;
   · перенос фото пальцем (первое — обложка), кольцо загрузки на плитке;
   · «Проверка»: карточка витрины (КарточкаГлавной) и разделы с «Изменить»; в правке — точка у изменённых шагов.
 Цвета — Theme (светлая и тёмная темы), слова — ПодачаText (ru/kk/en/ar).
 */

// MARK: - Модель: ошибки полей, порядок фото, изменения, превью

extension ПодачаМодель {
    /// Проверка не прошла: строка под полем, VoiceOver читает её сразу, телефон слегка вздрагивает.
    func пометить(_ поле: String, _ текст: String) {
        withAnimation(.easeOut(duration: 0.15)) { ошибкиПолей[поле] = текст }
        UIAccessibility.post(notification: .announcement, argument: текст)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    func ошибка(_ поле: String) -> String? { ошибкиПолей[поле] }

    /// Поле исправили — его строка ошибки уходит.
    func снятьОшибки(было: ФормаПодачи) {
        let ф = форма
        var снять: [String] = []
        if ф.название != было.название { снять.append("title") }
        if ф.раздел != было.раздел { снять.append("category") }
        if ф.описание != было.описание { снять.append("desc") }
        if ф.цена != было.цена || ф.торг != было.торг { снять.append("price") }
        if ф.ставка != было.ставка || ф.аренда != было.аренда { снять.append("price") }
        if ф.часы != было.часы || ф.часыС != было.часыС || ф.часыДо != было.часыДо { снять.append("hours") }
        if ф.город != было.город { снять.append("city") }
        if ф.работает != было.работает || ф.состояние != было.состояние { снять.append("works") }
        if ф.бренд != было.бренд || ф.модель != было.модель { снять.append("auto") }
        guard снять.contains(where: { ошибкиПолей[$0] != nil }) else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            for ключ in снять { ошибкиПолей.removeValue(forKey: ключ) }
        }
    }

    /// Перенос пальцем: плитка встаёт на место той, над которой её держат. Порядок уходит массивом images, как у сайта.
    func переставитьФото(_ id: UUID, к цели: UUID) {
        guard id != цели, let откуда = плитки.firstIndex(where: { $0.id == id }),
              let куда = плитки.firstIndex(where: { $0.id == цели }) else { return }
        var новые = плитки
        let плитка = новые.remove(at: откуда)
        новые.insert(плитка, at: куда)
        withAnimation(.easeInOut(duration: 0.2)) { плитки = новые }
    }

    /// Для VoiceOver: сдвинуть фото на одно место влево или вправо.
    func сдвинутьФото(_ id: UUID, на сдвиг: Int) {
        guard let откуда = плитки.firstIndex(where: { $0.id == id }) else { return }
        let куда = откуда + сдвиг
        guard куда >= 0, куда < плитки.count else { return }
        переставитьФото(id, к: плитки[куда].id)
    }

    /// Города для выбора: у выбранного района — его, иначе все города области (geoFillCities сайта).
    func городаСписка(_ регион: РегионКЗ?) -> [String] {
        guard let регион else { return [] }
        if !форма.район.isEmpty, let район = регион.районы.first(where: { $0.id == форма.район }) {
            return район.города
        }
        var все: [String] = []
        for район in регион.районы { все.append(contentsOf: район.города) }
        return все
    }

    /// Город вписывают сами: у области нет списка городов (у города республиканского значения город — сама область).
    var городВводом: Bool {
        guard let регион = справочники.регионы.first(where: { $0.id == форма.регион }) else { return true }
        if регион.город { return false }
        return городаСписка(регион).isEmpty
    }

    /// Номер шага среди видимых (с единицы) и сколько их всего — «Шаг 2 из 5».
    var номерШага: (номер: Int, всего: Int) {
        let шаги = видимыеШаги
        let номер = (шаги.firstIndex(of: шаг) ?? 0) + 1
        return (номер, max(1, шаги.count))
    }

    /// Правка: шаг, в котором что-то поменяли, помечается точкой.
    func изменён(_ ш: ШагПодачи) -> Bool {
        guard правка, let было = исходнаяФорма else { return false }
        if ш == .фото {
            return готовыеФото != исходныеФото || плитки.contains(where: { !$0.готова })
        }
        return Self.снимок(ш, форма) != Self.снимок(ш, было)
    }

    var естьИзменения: Bool { видимыеШаги.contains(where: { изменён($0) }) }

    /// Поля, которые показывает шаг, — одной строкой на поле: сравнивать было и стало.
    private static func снимок(_ ш: ШагПодачи, _ ф: ФормаПодачи) -> [String] {
        func да(_ з: Bool) -> String { з ? "1" : "0" }
        func пары<З>(_ словарь: [String: З]) -> String {
            словарь.keys.sorted().map { ключ in ключ + "=" + String(describing: словарь[ключ]!) }.joined(separator: ";")
        }
        switch ш {
        case .фото:
            return ф.фото
        case .данные:
            return [ф.название, ф.раздел, ф.описание, ф.бренд]
        case .характеристики:
            var итог = [ф.cpu, ф.gpu, ф.ram, ф.storage, ф.year, ф.vin, ф.модель, ф.поколение, ф.сделка, ф.вид]
            итог.append(пары(ф.недвижимость))
            итог.append(пары(ф.флагиНедвижимости))
            итог.append(пары(ф.запчасть))
            return итог
        case .цена:
            var итог = [ф.состояние, ф.работает, ф.цена, да(ф.торг), да(ф.аренда), ф.период, ф.ставка, ф.залог]
            итог.append(contentsOf: [ф.минСрок, ф.комплект, да(ф.тожеПродаю), да(ф.обмен), ф.склад])
            return итог
        case .адрес:
            return [ф.регион, ф.район, ф.город, ф.адрес, ф.часы, ф.часыС, ф.часыДо]
        case .дополнительно:
            return []
        case .проверка:
            return [да(ф.гарант)]
        }
    }

    /// Объявление для карточки витрины на «Проверке» — те же поля, по которым витрина рисует карточку.
    var товарДляПревью: Listing {
        let ф = форма
        let обложка = плитки.first(where: { $0.готова })?.url
        let цена = ценаЧислом
        let ставка = ставкаЧислом
        let название = ф.название.trimmingCharacters(in: .whitespacesAndNewlines)
        var товар = Listing(id: правка ? номерПравки : "preview",
                            title: название.isEmpty ? "—" : название,
                            price: цена > 0 ? Double(цена) : nil,
                            oldPrice: nil,
                            negotiable: ф.торг,
                            forRent: ф.аренда,
                            rentPriceDay: ставка > 0 ? Double(ставка) : nil,
                            thumb: обложка,
                            city: ф.город,
                            isTop: false,
                            isNew: ф.состояние == "new")
        товар.категория = ф.раздел.isEmpty ? nil : ф.раздел
        товар.состояние = состояниеВидно ? ф.состояние : nil
        товар.периодАренды = ф.аренда ? ф.период : nil
        товар.описание = ф.описание
        if режим == .недвижимость {
            let зеркало = зеркалоНедвижимости()
            товар.годСтрокой = зеркало["year"]
            товар.ramСтрокой = зеркало["ram"]
            товар.storageСтрокой = зеркало["storage"]
            товар.cpuСтрокой = зеркало["cpu"]
            товар.gpuСтрокой = зеркало["gpu"]
            var жильё = ф.недвижимость
            жильё["kind"] = ф.вид
            товар.жильё = жильё
        } else {
            товар.годСтрокой = ф.year.isEmpty ? nil : ф.year
            товар.ramСтрокой = ф.ram.isEmpty ? nil : ф.ram
            товар.storageСтрокой = ф.storage.isEmpty ? nil : ф.storage
            товар.cpuСтрокой = ф.cpu.isEmpty ? nil : ф.cpu
            товар.gpuСтрокой = ф.gpu.isEmpty ? nil : ф.gpu
        }
        return товар
    }

    /// Короткая строка «что заполнено» под названием шага на «Проверке».
    func сводка(_ ш: ШагПодачи) -> String {
        let ф = форма
        var части: [String] = []
        switch ш {
        case .фото:
            части.append(String(format: т("pc_photos"), готовыеФото.count))
        case .данные:
            части.append(ф.название.trimmingCharacters(in: .whitespacesAndNewlines))
            части.append(справочники.имя(ф.раздел))
        case .характеристики:
            части.append(contentsOf: сводкаХарактеристик())
            if !ф.vin.isEmpty { части.append("VIN " + ф.vin) }
        case .цена:
            части.append(сводкаЦены())
            if состояниеВидно {
                let подписи = подписиСостояния
                части.append(ф.состояние == "new" ? подписи.н : подписи.б)
            }
            if ф.обмен { части.append(т(услугаИлиРабота ? "form_ready_barter" : "form_ready_exchange")) }
        case .адрес:
            части.append(ф.город.trimmingCharacters(in: .whitespacesAndNewlines))
            части.append(ф.адрес.trimmingCharacters(in: .whitespacesAndNewlines))
        case .дополнительно:
            if ф.рассрочка { части.append(т("pay_installment")) }
            if ф.кредит { части.append(т("pay_credit")) }
            if ф.доставкаБесплатно { части.append(т("del_free_ship")) }
            if ф.гарантияДней > 0 { части.append(ШагДополнительно.срокГарантии(ф.гарантияДней)) }
            if !ф.знаки.isEmpty { части.append(т("wr_title") + ": " + String(ф.знаки.count)) }
        case .проверка:
            break
        }
        let итог = части.filter { !$0.isEmpty }.joined(separator: " · ")
        return итог.isEmpty ? т("rv_empty") : итог
    }

    private func сводкаХарактеристик() -> [String] {
        let ф = форма
        switch режим {
        case .авто:
            return [составитьНазваниеАвто(), ф.cpu, ф.gpu]
        case .недвижимость:
            return [названиеНедвижимости()]
        case .запчасти:
            var итог: [String] = []
            for поле in поляЗапчасти {
                let значение = ф.запчасть[поле.id] ?? ""
                guard !значение.isEmpty, итог.count < 4 else { continue }
                итог.append(поле.варианты.first(where: { $0.ключ == значение })?.подпись ?? значение)
            }
            return итог
        case .товар, .услуга, .работа:
            var итог: [String] = []
            for поле in характеристики {
                let значение: String
                switch поле.поле {
                case "cpu": значение = ф.cpu
                case "gpu": значение = ф.gpu
                case "ram": значение = ф.ram
                case "storage": значение = ф.storage
                default: значение = ф.year
                }
                if !значение.isEmpty { итог.append(значение) }
            }
            return итог
        }
    }

    private func сводкаЦены() -> String {
        if услугаИлиРабота {
            if ценаЧислом > 0 { return ПодачаМодель.деньги(ценаЧислом) + " ₸" }
            return т(форма.торг ? "price_negotiable" : "pc_no_price")
        }
        if форма.аренда && ставкаЧислом > 0 {
            let единица = т(форма.период == "month" ? "rent_price_month" : "form_price_per_day")
            return ПодачаМодель.деньги(ставкаЧислом) + " ₸ · " + единица
        }
        if ценаЧислом > 0 {
            let цена = ПодачаМодель.деньги(ценаЧислом) + " ₸"
            return форма.торг ? цена + " · " + т("torg_small") : цена
        }
        return форма.торг ? т("form_bargain") : ""
    }
}

// MARK: - Фокус полей

/// Поле, которое умеет получать фокус от панели над клавиатурой: .focused и метка для прокрутки.
struct ФокусПоля: ViewModifier {
    let фокус: FocusState<String?>.Binding?
    let ключ: String?

    init(фокус: FocusState<String?>.Binding?, ключ: String?) {
        self.фокус = фокус
        self.ключ = ключ
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if let фокус, let ключ {
            content
                .focused(фокус, equals: ключ)
                .id(ключ)
        } else {
            content
        }
    }
}

// MARK: - Строки под полем

/// Строка ошибки под полем (красная, с кружком): nil — ничего.
struct СтрокаОшибки: View {
    let текст: String?

    init(_ текст: String?) {
        self.текст = текст
    }

    var body: some View {
        if let текст, !текст.isEmpty {
            HStack(alignment: .top, spacing: 5) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityHidden(true)
                Text(текст)
                    .font(.system(size: 13, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Theme.скидкаТекст)
            .transition(.opacity)
        }
    }
}

/// Подсказка под полем — мелко и серым, одной-двумя строками.
struct ПодсказкаПоля: View {
    let текст: String

    init(_ текст: String) {
        self.текст = текст
    }

    var body: some View {
        Text(текст)
            .font(.system(size: 12))
            .foregroundStyle(Theme.текстВторой)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Сегмент и меню

/// Сегмент для 2–4 коротких вариантов; повторное нажатие снимает выбор, если можноСнять.
struct ВыборСегментом: View {
    let варианты: [ВариантПоля]
    @Binding var значение: String
    let можноСнять: Bool

    init(_ варианты: [ВариантПоля], значение: Binding<String>, можноСнять: Bool = false) {
        self.варианты = варианты
        self._значение = значение
        self.можноСнять = можноСнять
    }

    /// Влезет ли в одну строку телефона: 2–4 варианта и подписи короткие.
    static func влезет(_ варианты: [ВариантПоля]) -> Bool {
        guard варианты.count >= 2, варианты.count <= 4 else { return false }
        var всего = 0
        for в in варианты {
            if в.подпись.count > 14 { return false }
            всего += в.подпись.count
        }
        return всего <= 34
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(варианты, id: \.self) { в in
                кнопка(в)
            }
        }
        .padding(3)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
    }

    private func кнопка(_ в: ВариантПоля) -> some View {
        let выбран = значение == в.ключ
        return Button {
            if выбран {
                if можноСнять { значение = "" }
            } else {
                значение = в.ключ
            }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            Text(в.подпись)
                .font(.system(size: 14, weight: выбран ? Font.Weight.bold : Font.Weight.semibold))
                .foregroundStyle(выбран ? Theme.акцент : Theme.текст)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background {
                    if выбран {
                        RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous)
                            .fill(Theme.оттенокАкцента)
                            .overlay {
                                RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous)
                                    .strokeBorder(Theme.акцент, lineWidth: 1.5)
                            }
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(выбран ? .isSelected : [])
    }
}

/// Меню для средних списков (5–15 вариантов): «— не указано —», варианты с галочкой, «Другое (вписать)…».
struct МенюВыбора: View {
    let варианты: [ВариантПоля]
    @Binding var значение: String
    let подсказка: String
    let сброс: String?
    let своё: (() -> Void)?

    init(_ варианты: [ВариантПоля], значение: Binding<String>, подсказка: String, сброс: String? = nil,
         своё: (() -> Void)? = nil) {
        self.варианты = варианты
        self._значение = значение
        self.подсказка = подсказка
        self.сброс = сброс
        self.своё = своё
    }

    var body: some View {
        Menu {
            if let сброс {
                Button(сброс) { значение = "" }
            }
            ForEach(варианты, id: \.self) { в in
                Button {
                    значение = в.ключ
                } label: {
                    if значение == в.ключ {
                        Label(в.подпись, systemImage: "checkmark")
                    } else {
                        Text(в.подпись)
                    }
                }
            }
            if let своё {
                Divider()
                Button(ПодачаText.т("spec_other_write"), action: своё)
            }
        } label: {
            HStack(spacing: 8) {
                Text(показ.isEmpty ? подсказка : показ)
                    .font(.system(size: 16))
                    .foregroundStyle(показ.isEmpty ? Theme.текстВторой : Theme.текст)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 46)
            .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                    .strokeBorder(Theme.линия, lineWidth: 1.5)
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel(подсказка)
        .accessibilityValue(показ)
    }

    private var показ: String {
        варианты.first(where: { $0.ключ == значение })?.подпись ?? значение
    }
}

// MARK: - Цена

/// Большое поле суммы: цифры с пробелами между тысячами и «₸» справа.
struct ПолеЦены: View {
    @Binding var текст: String
    let заблокировано: Bool
    let ошибка: Bool
    let фокус: FocusState<String?>.Binding?
    let ключ: String?

    init(текст: Binding<String>, заблокировано: Bool = false, ошибка: Bool = false,
         фокус: FocusState<String?>.Binding? = nil, ключ: String? = nil) {
        self._текст = текст
        self.заблокировано = заблокировано
        self.ошибка = ошибка
        self.фокус = фокус
        self.ключ = ключ
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            TextField("0", text: $текст)
                .font(.system(size: 30, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .keyboardType(.numberPad)
                .disabled(заблокировано)
                .modifier(ФокусПоля(фокус: фокус, ключ: ключ))
            Text("₸")
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(Theme.текстВторой)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 64)
        .background(заблокировано ? Theme.поверхность2 : Theme.поверхность,
                    in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                .strokeBorder(ошибка ? Theme.ценаСкидка : Theme.линия, lineWidth: ошибка ? 2 : 1.5)
        }
    }
}

// MARK: - Кнопка «Назад» низа

/// Узкая вторичная кнопка «‹ Назад» — рядом с главной, чтобы главная была шире и заметнее.
struct КнопкаНазадПодачи: View {
    let действие: () -> Void

    init(действие: @escaping () -> Void) {
        self.действие = действие
    }

    var body: some View {
        Button(action: действие) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .accessibilityHidden(true)
                Text(ПодачаText.т("back"))
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(Theme.текст)
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                    .strokeBorder(Theme.линия, lineWidth: 1)
            }
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
    }
}

// MARK: - Лист разделов

/// Выбор раздела: поиск по всему дереву, большие строки со значками, «хлебные крошки» пути; раздел любого уровня можно
/// выбрать (catApply сайта работает на каждом уровне каскада).
struct ЛистРазделов: View {
    let справочники: СправочникиПодачи
    let выбрано: String
    let выбрать: (String) -> Void
    @Environment(\.dismiss) private var закрыть
    @State private var поиск = ""
    @State private var путь: [String]

    init(справочники: СправочникиПодачи, выбрано: String, выбрать: @escaping (String) -> Void) {
        self.справочники = справочники
        self.выбрано = выбрано
        self.выбрать = выбрать
        /* Открываем там, где лежит выбранный раздел: путь — его предки. */
        let цепочка = выбрано.isEmpty ? [] : справочники.цепочка(выбрано)
        _путь = State(initialValue: Array(цепочка.dropLast()))
    }

    private func т(_ ключ: String) -> String { ПодачаText.т(ключ) }

    var body: some View {
        NavigationStack {
            List {
                if запрос.isEmpty {
                    if !путь.isEmpty {
                        Section {
                            строкаЦеликом
                        } header: {
                            крошки
                        }
                    }
                    Section {
                        ForEach(текущие, id: \.self) { ключ in
                            строка(ключ)
                        }
                    }
                } else {
                    Section {
                        if найдено.isEmpty {
                            Text(т("cat_empty"))
                                .foregroundStyle(Theme.текстВторой)
                        }
                        ForEach(найдено, id: \.self) { ключ in
                            строкаПоиска(ключ)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $поиск, placement: .navigationBarDrawer(displayMode: .always), prompt: Text(т("cat_search")))
            .navigationTitle(т("cat_pick"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(т("close")) { закрыть() }
                }
            }
        }
        .tint(Theme.акцент)
    }

    private var запрос: String {
        поиск.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var текущие: [String] {
        guard let последний = путь.last else { return справочники.корни }
        return справочники.разделы[последний]?.дети ?? []
    }

    /// Совпадения по всему дереву: сначала те, что начинаются с запроса, потом короткие.
    private var найдено: [String] {
        let q = запрос
        guard !q.isEmpty else { return [] }
        var начало: [String] = []
        var внутри: [String] = []
        for (ключ, раздел) in справочники.разделы {
            let имя = раздел.имя.lowercased()
            if имя.hasPrefix(q) {
                начало.append(ключ)
            } else if имя.contains(q) {
                внутри.append(ключ)
            }
        }
        let порядок: (String, String) -> Bool = { a, b in
            let имяA = справочники.имя(a)
            let имяB = справочники.имя(b)
            if имяA.count != имяB.count { return имяA.count < имяB.count }
            return имяA < имяB
        }
        return Array((начало.sorted(by: порядок) + внутри.sorted(by: порядок)).prefix(60))
    }

    /// «Все категории › Электроника › Телефоны»: нажатие — вернуться на тот уровень.
    private var крошки: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Button(т("cat_all")) { withAnimation { путь = [] } }
                ForEach(Array(путь.enumerated()), id: \.offset) { номер, ключ in
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.текстВторой)
                        .accessibilityHidden(true)
                    Button(справочники.имя(ключ)) {
                        withAnimation { путь = Array(путь.prefix(номер + 1)) }
                    }
                    .disabled(номер == путь.count - 1)
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .textCase(nil)
        }
    }

    /// Выбрать сам раздел, в котором стоим («Выбрать «Телефоны»»).
    @ViewBuilder
    private var строкаЦеликом: some View {
        if let последний = путь.last {
            Button {
                выбрать(последний)
                закрыть()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.акцент)
                        .frame(width: 38, height: 38)
                        .accessibilityHidden(true)
                    Text(String(format: т("cat_take"), справочники.имя(последний)))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.акцент)
                    Spacer(minLength: 0)
                    if последний == выбрано {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Theme.акцент)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func строка(_ ключ: String) -> some View {
        let дети = справочники.разделы[ключ]?.дети ?? []
        let примеры = дети.prefix(3).map { справочники.имя($0) }.joined(separator: ", ")
        return Button {
            if дети.isEmpty {
                выбрать(ключ)
                закрыть()
            } else {
                withAnimation { путь.append(ключ) }
            }
        } label: {
            HStack(spacing: 12) {
                ЗначокРаздела(корень: справочники.корень(ключ))
                VStack(alignment: .leading, spacing: 2) {
                    Text(справочники.имя(ключ))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.текст)
                    if !примеры.isEmpty {
                        Text(примеры + (дети.count > 3 ? "…" : ""))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.текстВторой)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if ключ == выбрано || справочники.цепочка(выбрано).contains(ключ) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.акцент)
                        .accessibilityHidden(true)
                }
                if !дети.isEmpty {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.текстВторой)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(ключ == выбрано ? .isSelected : [])
    }

    /// Строка поиска: имя и путь к нему серым («Электроника › Телефоны»).
    private func строкаПоиска(_ ключ: String) -> some View {
        let предки = справочники.цепочка(ключ).dropLast().map { справочники.имя($0) }
        return Button {
            выбрать(ключ)
            закрыть()
        } label: {
            HStack(spacing: 12) {
                ЗначокРаздела(корень: справочники.корень(ключ))
                VStack(alignment: .leading, spacing: 2) {
                    Text(справочники.имя(ключ))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.текст)
                    if !предки.isEmpty {
                        Text(предки.joined(separator: " › "))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.текстВторой)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if ключ == выбрано {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.акцент)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Значок корня раздела в мятном квадрате.
struct ЗначокРаздела: View {
    let корень: String

    init(корень: String) {
        self.корень = корень
    }

    static func символ(_ корень: String) -> String {
        switch корень {
        case "electronics": return "iphone"
        case "transport": return "car"
        case "realty": return "house"
        case "clothing": return "tshirt"
        case "home-garden": return "sofa"
        case "kids": return "figure.and.child.holdinghands"
        case "sport": return "figure.run"
        case "animals": return "pawprint"
        case "jobs": return "briefcase"
        case "services": return "wrench.and.screwdriver"
        case "hobby": return "paintpalette"
        case "food-farm": return "carrot"
        case "beauty": return "sparkles"
        default: return "square.grid.2x2"
        }
    }

    var body: some View {
        Image(systemName: Self.символ(корень))
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Theme.акцент)
            .frame(width: 38, height: 38)
            .background(Theme.мята, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Строка выбранного раздела в форме: значок, имя и путь; пусто — «Выберите категорию».
struct СтрокаРаздела: View {
    let справочники: СправочникиПодачи
    let раздел: String
    let ошибка: Bool
    let действие: () -> Void

    init(справочники: СправочникиПодачи, раздел: String, ошибка: Bool, действие: @escaping () -> Void) {
        self.справочники = справочники
        self.раздел = раздел
        self.ошибка = ошибка
        self.действие = действие
    }

    var body: some View {
        let цепочка = раздел.isEmpty ? [] : справочники.цепочка(раздел)
        let предки = цепочка.dropLast().map { справочники.имя($0) }
        let имя = справочники.имя(раздел)
        return Button(action: действие) {
            HStack(spacing: 12) {
                ЗначокРаздела(корень: раздел.isEmpty ? "" : справочники.корень(раздел))
                VStack(alignment: .leading, spacing: 2) {
                    Text(имя.isEmpty ? ПодачаText.т("cat_pick") : имя)
                        .font(.system(size: 16, weight: имя.isEmpty ? Font.Weight.regular : Font.Weight.semibold))
                        .foregroundStyle(имя.isEmpty ? Theme.текстВторой : Theme.текст)
                        .lineLimit(1)
                    if !предки.isEmpty {
                        Text(предки.joined(separator: " › "))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.текстВторой)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 58)
            .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                    .strokeBorder(ошибка ? Theme.ценаСкидка : Theme.линия, lineWidth: ошибка ? 2 : 1.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ПодачаText.т("form_category"))
        .accessibilityValue(имя)
    }
}

// MARK: - Перенос фото пальцем

/// Плитку держат над другой — она встаёт на её место (live-перестановка, как в «Фото» iOS).
struct ПереносФото: DropDelegate {
    let цель: UUID
    @Binding var тащим: UUID?
    let переставить: (UUID, UUID) -> Void

    init(цель: UUID, тащим: Binding<UUID?>, переставить: @escaping (UUID, UUID) -> Void) {
        self.цель = цель
        self._тащим = тащим
        self.переставить = переставить
    }

    func dropEntered(info: DropInfo) {
        guard let тащим, тащим != цель else { return }
        переставить(тащим, цель)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        тащим = nil
        return true
    }
}

/// Отпустили мимо плиток — перенос закончен.
struct КонецПереносаФото: DropDelegate {
    @Binding var тащим: UUID?

    init(тащим: Binding<UUID?>) {
        self._тащим = тащим
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        тащим = nil
        return true
    }
}

/// Кольцо загрузки на плитке: сжимаем (треть) → отправляем (две трети), подпись под ним.
struct КольцоЗагрузки: View {
    let этап: Int

    init(этап: Int) {
        self.этап = этап
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: этап >= 1 ? 0.7 : 0.3)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: этап)
                ProgressView()
                    .tint(Color.white)
                    .scaleEffect(0.6)
            }
            .frame(width: 34, height: 34)
            Text(ПодачаText.т(этап >= 1 ? "ph_stage_up" : "ph_stage_prep"))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ПодачаText.т(этап >= 1 ? "ph_stage_up" : "ph_stage_prep"))
    }
}

// MARK: - «Проверка»: карточка витрины и разделы с «Изменить»

/// Карточка, как её покажет витрина (КарточкаГлавной из SiteCards), по центру.
struct КарточкаВитриныПодачи: View {
    @ObservedObject var модель: ПодачаМодель

    init(модель: ПодачаМодель) {
        self.модель = модель
    }

    var body: some View {
        let вид = ВидКарточкиГлавной(ряда: модель.корень)
        let подраздел: String? = вид == .техника ? модель.справочники.имя(модель.форма.раздел) : nil
        return HStack {
            Spacer(minLength: 0)
            КарточкаГлавной(товар: модель.товарДляПревью, вид: вид, подраздел: подраздел)
                .frame(width: 210)
                .allowsHitTesting(false)
            Spacer(minLength: 0)
        }
    }
}

/// Список шагов на «Проверке»: название, что заполнено, «Изменить» — перейти на шаг. В правке — метка «изменено».
struct РазделыПроверки: View {
    @ObservedObject var модель: ПодачаМодель

    init(модель: ПодачаМодель) {
        self.модель = модель
    }

    private func т(_ ключ: String) -> String { ПодачаText.т(ключ) }

    var body: some View {
        VStack(spacing: 0) {
            let шаги = модель.видимыеШаги.filter { $0 != .проверка }
            ForEach(Array(шаги.enumerated()), id: \.element) { номер, ш in
                if номер > 0 {
                    Rectangle().fill(Theme.линия).frame(height: 1)
                }
                строка(ш)
            }
        }
    }

    private func строка(_ ш: ШагПодачи) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: ШагПодачи.значок(ш))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.акцент)
                .frame(width: 32, height: 32)
                .background(Theme.мята, in: RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(ш.название)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.текст)
                    if модель.изменён(ш) {
                        Text(т("edited"))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.золото)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Theme.топФон, in: Capsule())
                    }
                }
                Text(модель.сводка(ш))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
                    .lineLimit(2)
            }
            Spacer(minLength: 6)
            Button(т("change")) { модель.перейти(к: ш) }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.акцент)
                .buttonStyle(.plain)
                .accessibilityLabel(т("change") + ": " + ш.название)
        }
        .padding(.vertical, 10)
    }
}

extension ШагПодачи {
    /// Значок шага для полосы правки и «Проверки».
    static func значок(_ ш: ШагПодачи) -> String {
        switch ш {
        case .фото: return "photo.on.rectangle"
        case .данные: return "text.alignleft"
        case .характеристики: return "list.bullet.rectangle"
        case .цена: return "tag"
        case .адрес: return "mappin.and.ellipse"
        case .дополнительно: return "slider.horizontal.3"
        case .проверка: return "checkmark.seal"
        }
    }
}
