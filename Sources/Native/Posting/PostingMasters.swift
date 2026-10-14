import SwiftUI
import UIKit

/**
 МАСТЕРА ПОДАЧИ ПОВЕРХ ШАГОВ (TestFlight, владелец: «при подаче авто сначала выбираться должен бренд и модель, затем
 фото — нужна правильная логика добавления»).

 Как у сайта: выбрал «Транспорт → Легковая» на старте — сразу открывается мастер авто (_asAutoGo → autoWizOpen):
 Марка (поиск, «Популярные», группы справочника /api/auto_models.php?brands=1, «Другая марка — вписать») → Модель
 (/api/auto_models.php?brand=, «Другая модель — вписать»; кузов ставит сама модель) → Поколение (только когда их
 больше одного) → «Об автомобиле» одним экраном (год, пробег регулятором, топливо, объём, коробка — AutoPickers.swift;
 год и пробег обязательны, _aw2SyncNext) → «Готово»: марка, модель, поколение, год, пробег (ram), объём (storage),
 коробка (cpu), топливо (gpu) — в форму, название собирается само (autoTitleCompose), дальше — фото. У мото, грузового
 и водного первым шагом — уточнение типа (_asRenderAutoKids). Выбор недвижимости на старте так же сразу открывает
 мастер объекта (_asRealtyGo → realtyWizOpen): сделка и вид → параметры → условия → проверка, «Сохранить» —
 REALTY_DATA, название и описание собираются. Оба мастера открываются и позже — карточкой параметров на «Фото» и
 «Характеристиках» (#aw2-entry, #rw2-entry). Свайп от края окна мастера — то же, что «Назад» (EdgeSwipeBack.swift).
 */

// MARK: - Полоса хода

/// Полоса хода из сегментов (.ast-line и .rw2-prog): пройденные — зелёные, текущий — акцент, впереди — серая дорожка.
struct ПолосаШаговПодачи: View {
    let всего: Int
    let текущий: Int

    init(всего: Int, текущий: Int) {
        self.всего = всего
        self.текущий = текущий
    }

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<max(1, всего), id: \.self) { номер in
                Capsule()
                    .fill(цвет(номер))
                    .frame(maxWidth: .infinity)
                    .frame(height: 5)
            }
        }
        .animation(ДвижениеСайта.шаг, value: текущий)
        .accessibilityHidden(true)
    }

    private func цвет(_ номер: Int) -> Color {
        if номер < текущий { return Theme.зелёный2 }
        if номер == текущий { return КраскаПодачи.акцентТекст }
        return Theme.цвет(светлый: Theme.hex(0xD2DFD7), тёмный: Theme.hex(0xFFFFFF, 0.16))
    }
}

// MARK: - Окно мастера (.rw2)

/// Окно мастера .rw2: шапка .rw2-hd (значок, заголовок, «Шаг N из M», сброс, «✕»), полоса хода, тело с прокруткой,
/// низ .rw2-ft («Назад» / «Отмена» и «Далее» / «Готово»; недоступная «Далее» — бледная).
struct ОкноМастераПодачи<Тело: View>: View {
    let значок: String
    let заголовок: String
    let шаг: Int
    let всего: Int
    let далееПодпись: String
    let можноДалее: Bool
    let подсказкаДалее: String?
    let сброс: (() -> Void)?
    let закрыть: () -> Void
    let назад: () -> Void
    let далее: () -> Void
    let тело: Тело

    init(значок: String, заголовок: String, шаг: Int, всего: Int, далееПодпись: String, можноДалее: Bool,
         подсказкаДалее: String? = nil, сброс: (() -> Void)? = nil, закрыть: @escaping () -> Void,
         назад: @escaping () -> Void, далее: @escaping () -> Void, @ViewBuilder тело: () -> Тело) {
        self.значок = значок
        self.заголовок = заголовок
        self.шаг = шаг
        self.всего = всего
        self.далееПодпись = далееПодпись
        self.можноДалее = можноДалее
        self.подсказкаДалее = подсказкаДалее
        self.сброс = сброс
        self.закрыть = закрыть
        self.назад = назад
        self.далее = далее
        self.тело = тело()
    }

    private func т(_ ключ: String) -> String { МастерПодачиText.т(ключ) }

    var body: some View {
        VStack(spacing: 0) {
            шапка
            ScrollViewReader { прокрутка in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Color.clear.frame(height: 0).id("верх")
                        тело
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: шаг) { _, _ in
                    withAnimation(ДвижениеСайта.прокрутка) { прокрутка.scrollTo("верх", anchor: .top) }
                }
            }
            низ
        }
        /* Смахнуть от края экрана — то же, что «Назад» (на первом шаге — «Отмена»: мастер закрывается). Фон — после
           жеста: за пальцем едет только содержимое, у края не открывается полоса системного фона окна. */
        .смахиваниеНазад { назад() }
        .background(КраскаПодачи.фон.ignoresSafeArea())
    }

    private var шапка: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: значок)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(КраскаПодачи.хорошоТекст)
                    .frame(width: 38, height: 38)
                    .background(КраскаПодачи.хорошоФон, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(заголовок)
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(КраскаПодачи.текст)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .accessibilityAddTraits(.isHeader)
                    Text(String(format: т("m_step"), шаг + 1, max(1, всего)))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.текстВторой)
                }
                Spacer(minLength: 4)
                if let сброс {
                    Button(action: сброс) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.текстВторой)
                            .frame(width: 34, height: 34)
                            .background(КраскаПодачи.поле, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(т("m_reset"))
                }
                КнопкаЗакрытьПодачи(действие: закрыть)
            }
            ПолосаШаговПодачи(всего: всего, текущий: шаг)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(КраскаПодачи.карточка.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) {
            Rectangle().fill(КраскаПодачи.линия).frame(height: 1)
        }
    }

    private var низ: some View {
        VStack(spacing: 8) {
            if !можноДалее, let подсказкаДалее, !подсказкаДалее.isEmpty {
                Text(подсказкаДалее)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                    .frame(maxWidth: .infinity)
            }
            HStack(spacing: 10) {
                КнопкаПодачиВторая(т(шаг == 0 ? "m_cancel" : "m_back")) { назад() }
                Button(action: далее) {
                    HStack(spacing: 6) {
                        Text(далееПодпись)
                            .font(.system(size: 16, weight: .heavy))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .heavy))
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(LinearGradient(colors: [Theme.зелёный, Theme.зелёный2], startPoint: .topLeading,
                                               endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                    .opacity(можноДалее ? 1 : 0.5)
                }
                .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
                .disabled(!можноДалее)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(КраскаПодачи.карточка.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle().fill(КраскаПодачи.линия).frame(height: 1)
        }
    }
}

/// Вопрос шага мастера (.flow-q и .flow-sub): крупный заголовок и пояснение серым.
struct ВопросМастераПодачи: View {
    let вопрос: String
    let пояснение: String

    init(_ вопрос: String, пояснение: String = "") {
        self.вопрос = вопрос
        self.пояснение = пояснение
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(вопрос)
                .font(.system(size: 20, weight: .heavy))
                .kerning(-0.3)
                .foregroundStyle(КраскаПодачи.текст)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if !пояснение.isEmpty {
                Text(пояснение)
                    .font(.system(size: 13))
                    .lineSpacing(2)
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Кнопка-плитка мастера (.aw2-b / .rw2-tile): значок или буква в круге, подпись, счётчик справа; выбранная — зелёная.
struct ПлиткаМастераПодачи: View {
    let подпись: String
    let пояснение: String
    let значок: String?
    let буква: String?
    let счётчик: String
    /// Марка — знак с сайта (img/brands) вместо буквы; нет знака или не загрузился — буква.
    let логотипМарки: String?
    let выбрана: Bool
    let действие: () -> Void

    init(_ подпись: String, пояснение: String = "", значок: String? = nil, буква: String? = nil, счётчик: String = "",
         логотипМарки: String? = nil, выбрана: Bool, действие: @escaping () -> Void) {
        self.подпись = подпись
        self.пояснение = пояснение
        self.значок = значок
        self.буква = буква
        self.счётчик = счётчик
        self.логотипМарки = логотипМарки
        self.выбрана = выбрана
        self.действие = действие
    }

    var body: some View {
        Button(action: действие) {
            HStack(spacing: 10) {
                знак
                VStack(alignment: .leading, spacing: 1) {
                    Text(подпись)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(КраскаПодачи.текст)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .multilineTextAlignment(.leading)
                    if !пояснение.isEmpty {
                        Text(пояснение)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.текстВторой)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if !счётчик.isEmpty {
                    Text(счётчик)
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundStyle(Theme.текстВторой)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(КраскаПодачи.поле, in: Capsule())
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(выбрана ? КраскаПодачи.хорошоФон : КраскаПодачи.карточка,
                        in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                    .strokeBorder(выбрана ? КраскаПодачи.акцентТекст : КраскаПодачи.линия, lineWidth: выбрана ? 1.5 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
        .accessibilityAddTraits(выбрана ? .isSelected : [])
    }

    @ViewBuilder
    private var знак: some View {
        if let значок {
            Image(systemName: значок)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(КраскаПодачи.хорошоТекст)
                .frame(width: 30, height: 30)
                .background(КраскаПодачи.поле, in: Circle())
                .accessibilityHidden(true)
        } else if let марка = логотипМарки {
            ЗнакМаркиСайта(марка, размер: 30) {
                кругБуквы(буква ?? String(марка.prefix(1)).uppercased())
            }
        } else if let буква {
            кругБуквы(буква)
        }
    }

    private func кругБуквы(_ буква: String) -> some View {
        Text(буква)
            .font(.system(size: 14, weight: .heavy))
            .foregroundStyle(КраскаПодачи.хорошоТекст)
            .frame(width: 30, height: 30)
            .background(КраскаПодачи.хорошоФон, in: Circle())
            .accessibilityHidden(true)
    }
}

/// Поиск в мастере (.inp «Поиск марки»): лупа, поле, «✕» очистить.
struct ПоискМастераПодачи: View {
    let подсказка: String
    @Binding var текст: String

    init(_ подсказка: String, текст: Binding<String>) {
        self.подсказка = подсказка
        self._текст = текст
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.текстВторой)
                .accessibilityHidden(true)
            TextField(подсказка, text: $текст)
                .font(.system(size: 16))
                .foregroundStyle(КраскаПодачи.текст)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
            if !текст.isEmpty {
                Button { текст = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.текстВторой)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(МастерПодачиText.т("m_reset"))
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 46)
        .background(КраскаПодачи.карточка, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                .strokeBorder(КраскаПодачи.линия, lineWidth: 1)
        }
    }
}

/// «Другая марка — вписать» (.aw2-other): кнопка с «+», по нажатию — поле и «Готово».
struct СвоёЗначениеМастера: View {
    let подпись: String
    let подсказка: String
    let готово: (String) -> Void
    @State private var открыто = false
    @State private var текст = ""
    @FocusState private var фокус: Bool

    init(подпись: String, подсказка: String, открыто: Bool = false, готово: @escaping (String) -> Void) {
        self.подпись = подпись
        self.подсказка = подсказка
        self.готово = готово
        _открыто = State(initialValue: открыто)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ПлиткаМастераПодачи(подпись, значок: "plus", выбрана: открыто) {
                открыто.toggle()
                if открыто { фокус = true }
            }
            if открыто {
                HStack(spacing: 8) {
                    TextField(подсказка, text: ограниченный)
                        .font(.system(size: 16))
                        .foregroundStyle(КраскаПодачи.текст)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(true)
                        .focused($фокус)
                        .submitLabel(.done)
                        .onSubmit { принять() }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 46)
                        .background(КраскаПодачи.поле, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                                .strokeBorder(КраскаПодачи.линия, lineWidth: 1)
                        }
                    Button {
                        принять()
                    } label: {
                        Text(МастерПодачиText.т("m_done"))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 46)
                            .background(Theme.зелёный, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var ограниченный: Binding<String> {
        let связь = $текст
        return Binding(get: { связь.wrappedValue }, set: { новое in
            связь.wrappedValue = ПределыПодачи.обрезать(новое, ПределыПодачи.короткое)
        })
    }

    private func принять() {
        let чистое = текст.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !чистое.isEmpty else {
            ОткликСайта.предупреждение()
            UIAccessibility.post(notification: .announcement, argument: МастерПодачиText.т("aw_other_need"))
            return
        }
        фокус = false
        готово(чистое)
    }
}

// MARK: - Мастер авто (_aw2)

/**
 Мастер авто (autoWizOpen сайта): держит выбор у себя и пишет в форму только по «Готово» (autoWizApply); «✕» —
 закрыть без изменений. Шаги — как у сайта сейчас (ultra-site 14.10.2026): легковая — марка → модель → поколение (только
 когда их у модели больше одного; одно ставится само) → «Об автомобиле»: год, пробег, топливо, объём, коробка и, если
 надо, кузов — одним экраном (AutoPickers.swift). Подраздел кузова ставит модель (models[].body): один — он и встанет,
 несколько или нет данных — чипом по желанию, без выбора — cars. Мото, грузовой, водный — уточнение типа первым шагом
 (только со старта), дальше те же марка, модель и параметры; обязательна у них одна марка.
 */
struct МастерАвтоВид: View {
    @ObservedObject var модель: ПодачаМодель

    private enum Шаг: Hashable { case кузов, марка, модель, поколение, параметры }

    /// Уточнение типа (дети раздела со старта) — не у легковой; в State: выбор меняет раздел формы, а шаги мастера не должны.
    @State private var кузова: [String]
    @State private var верхКузова: String
    @State private var шаг: Шаг
    /// Шли вперёд — новый шаг въезжает по ходу, назад — с другой стороны.
    @State private var вперёд = true
    /// Легковая — подраздел кузова (cars-*), уйдёт в форму по «Готово» (пусто — cars); прочий транспорт — выбранный тип.
    @State private var кузов: String
    @State private var марка: String
    @State private var модельАвто: String
    @State private var поколение: String
    @State private var год: String
    @State private var пробег: String
    @State private var объём: String
    @State private var коробка: String
    @State private var топливо: String
    @State private var модели: [МодельАвто] = []
    @State private var моделиГрузятся = false
    @State private var поиск = ""
    /// «Марка|модель|поколение», для которых уже отмечено заранее (заготовить) — снятое человеком не возвращается.
    @State private var заготовлено: String
    /// Что заготовить() отметил сам: «топливо», «коробка», «объём» → значение. Другая машина — нетронутое снимается.
    @State private var автоОтмечено: [String: String] = [:]
    /// Кузов, модель и год, с которыми мастер открыли: раздел, выбранный человеком, при той же модели не трогаем, а год
    /// формы виден среди лет поколения, даже если справочник его не знает.
    @State private var исходныйКузов: String
    @State private var исходнаяМодель: String
    @State private var исходныйГод: String
    @Environment(\.layoutDirection) private var направление

    /// форма — снимок полей при открытии (autoWizOpen: значения из f-brand, f-model, f-gen, f-year…).
    init(модель: ПодачаМодель, форма: ФормаПодачи, кузова: [String], сКузовом: Bool) {
        self.модель = модель
        /* Подразделы легковой — cars-* (cars-sedan, cars-suv…). У легковой экрана «Какой кузов?» больше нет:
           подраздел ставит модель. */
        let легковая = форма.раздел == "cars" || форма.раздел.hasPrefix("cars-")
        let показатьКузов = сКузовом && !кузова.isEmpty && !легковая
        _кузова = State(initialValue: показатьКузов ? кузова : [])
        _верхКузова = State(initialValue: форма.раздел)
        _шаг = State(initialValue: показатьКузов ? .кузов : .марка)
        let кузов = легковая && форма.раздел != "cars" ? форма.раздел : ""
        _кузов = State(initialValue: кузов)
        _исходныйКузов = State(initialValue: кузов)
        let марка = форма.бренд.trimmingCharacters(in: .whitespaces)
        let модельАвто = форма.модель.trimmingCharacters(in: .whitespaces)
        _марка = State(initialValue: марка)
        _модельАвто = State(initialValue: модельАвто)
        _исходнаяМодель = State(initialValue: модельАвто)
        _поколение = State(initialValue: форма.поколение)
        _год = State(initialValue: форма.year)
        _исходныйГод = State(initialValue: форма.year)
        let пробег = форма.ram.trimmingCharacters(in: .whitespaces)
        _пробег = State(initialValue: Int(пробег) != nil ? пробег : ПодачаМодель.цифры(пробег, предел: 7))
        _объём = State(initialValue: форма.storage)
        _коробка = State(initialValue: форма.cpu)
        _топливо = State(initialValue: форма.gpu)
        /* Мастер уже заполнял форму (год есть) — заранее ничего не отмечаем: снятое тогда пусть остаётся снятым. */
        let ключ = [марка, модельАвто, форма.поколение].joined(separator: "|")
        _заготовлено = State(initialValue: форма.year.isEmpty ? "" : ключ)
    }

    private func т(_ ключ: String) -> String { МастерПодачиText.т(ключ) }
    private func тп(_ ключ: String) -> String { ПараметрыАвтоText.т(ключ) }

    /// AW_GEAR и AW_FUEL сайта — слова фильтра витрины, уходят по-русски на любом языке.
    private static let коробки = ["Автомат", "Механика", "Робот", "Вариатор"]
    private static let топлива = ["Бензин", "Дизель", "Газ", "Гибрид", "Электро"]
    private static let электро = "Электро"
    private static let автомат = "Автомат"
    /// Ходовые объёмы легковых, л — когда у поколения нет gens[].eng.
    private static let ходовыеОбъёмы = ["0.8", "1.0", "1.2", "1.3", "1.4", "1.5", "1.6", "1.8", "2.0", "2.2", "2.4",
                                        "2.5", "2.7", "3.0", "3.5", "4.0", "4.5", "4.6", "5.7"]
    /// Начало ленты годов, когда поколения нет.
    private static let первыйГод = 1960
    /// Самые частые марки Казахстана — наверху сетки (только те, что есть в справочнике сайта); их же «Популярные» в
    /// выборе марки листа «Фильтры» (Filters/FilterViews.swift).
    static let популярные = ["Toyota", "Hyundai", "Kia", "Chevrolet", "Lada", "Volkswagen", "Lexus",
                             "Mercedes-Benz", "BMW", "Nissan", "Mitsubishi", "Audi", "Honda", "Mazda",
                             "Chery", "Haval", "Geely", "Skoda", "Renault", "Subaru"]

    private let колонки = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    /// Легковая: cars и его кузова (cars-*).
    private static func этоЛегковая(_ раздел: String, _ справочники: СправочникиПодачи) -> Bool {
        раздел == "cars" || раздел.hasPrefix("cars-") || справочники.внутри(раздел, ["cars"])
    }

    /// Легковая сейчас: на шаге уточнения типа (транспорт со старта) раздел формы меняется на глазах.
    private var легковая: Bool { Self.этоЛегковая(модель.форма.раздел, модель.справочники) }

    /// Шаги, которые есть: тип — только не у легковой и со старта, поколение — только когда выбирать есть из чего.
    private var шаги: [Шаг] {
        var итог: [Шаг] = кузова.isEmpty ? [] : [.кузов]
        итог.append(.марка)
        итог.append(.модель)
        if поколенияМодели.count > 1 { итог.append(.поколение) }
        итог.append(.параметры)
        return итог
    }

    /// Номер шага среди существующих; шага в списке уже нет (поколения пропали) — считаем от модели.
    private var номер: Int {
        шаги.firstIndex(of: шаг) ?? шаги.firstIndex(of: .модель) ?? 0
    }

    var body: some View {
        ОкноМастераПодачи(значок: "car", заголовок: заголовок, шаг: номер, всего: шаги.count,
                          далееПодпись: т(шаг == .параметры ? "m_done" : "m_next"), можноДалее: можноДалее,
                          подсказкаДалее: шаг == .параметры && легковая ? т("aw_need_nums") : nil,
                          сброс: { сбросить() }, закрыть: { закрыть() }, назад: { назад() }, далее: { далее() }) {
            ZStack(alignment: .topLeading) {
                содержимое
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(шаг)
                    .transition(переход)
            }
        }
        .task { await модель.загрузитьМарки() }
        .task(id: марка) { await загрузитьМодели() }
    }

    private var заголовок: String {
        if марка.isEmpty { return т("aw_car") }
        return модельАвто.isEmpty ? марка : марка + " " + модельАвто
    }

    /// Новый шаг въезжает чуть сбоку по ходу (вперёд — с конца строки, назад — с начала), прежний гаснет.
    private var переход: AnyTransition {
        let знак: CGFloat = направление == .rightToLeft ? -1 : 1
        let сдвиг: CGFloat = (вперёд ? 28 : -28) * знак
        return AnyTransition.asymmetric(insertion: AnyTransition.opacity.combined(with: AnyTransition.offset(x: сдвиг)),
                                        removal: AnyTransition.opacity)
    }

    @ViewBuilder
    private var содержимое: some View {
        switch шаг {
        case .кузов: шагКузов
        case .марка: шагМарка
        case .модель: шагМодель
        case .поколение: шагПоколение
        case .параметры: шагПараметры
        }
    }

    // MARK: Кузов (_asRenderAutoKids) — мото, грузовой, водный

    private var шагКузов: some View {
        let имяВерха = модель.справочники.имя(верхКузова)
        let вопрос = верхКузова == "cars" ? т("aw_body_cars") : (верхКузова == "motorcycles" ? т("aw_body_moto") : т("aw_body_other"))
        return VStack(alignment: .leading, spacing: 14) {
            ВопросМастераПодачи(вопрос, пояснение: String(format: т("aw_body_s"), имяВерха.isEmpty ? т("aw_car") : имяВерха))
            LazyVGrid(columns: колонки, spacing: 8) {
                ForEach(кузова, id: \.self) { к in
                    ПлиткаМастераПодачи(имяРаздела(к), значок: ЗначокРазделаПодачи.символ("transport"),
                                        выбрана: кузов == к) {
                        выбратьКузов(к)
                    }
                }
            }
            Button {
                кузов = ""
                перейти(.марка)
            } label: {
                Text(т("aw_body_skip"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(КраскаПодачи.текст)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 40)
                    .background(КраскаПодачи.поле, in: Capsule())
                    .overlay { Capsule().strokeBorder(КраскаПодачи.линия, lineWidth: 1) }
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func имяРаздела(_ ключ: String) -> String {
        let имя = модель.справочники.имя(ключ)
        return имя.isEmpty ? ключ : имя
    }

    @MainActor
    private func выбратьКузов(_ ключ: String) {
        кузов = ключ
        /* _asAutoGo(kid): раздел типа ставится сразу — от него зависят поля экрана параметров. */
        модель.выбратьРаздел(ключ)
        ОткликСайта.выбор()
        перейти(.марка)
    }

    // MARK: Марка (_awStepBrand)

    private var шагМарка: some View {
        VStack(alignment: .leading, spacing: 12) {
            ВопросМастераПодачи(т("aw_brand"))
            if модель.маркиАвто.isEmpty && !модель.маркиНеДоступны {
                загрузка
            } else if модель.маркиАвто.isEmpty {
                ЗаметкаПодачи(т("aw_brands_none"), тон: .серый)
                СвоёЗначениеМастера(подпись: т("aw_brand_other"), подсказка: т("aw_brand_other_ph"), открыто: true) { своё in
                    выбратьМарку(своё)
                }
            } else {
                ПоискМастераПодачи(т("aw_brand_search"), текст: $поиск)
                СвоёЗначениеМастера(подпись: т("aw_brand_other"), подсказка: т("aw_brand_other_ph")) { своё in
                    выбратьМарку(своё)
                }
                if чистыйПоиск.isEmpty {
                    ForEach(группы) { группа in
                        подписьГруппы(группа.регион)
                        сеткаМарок(группа.марки)
                    }
                } else if найденныеМарки.isEmpty {
                    ПодсказкаПоля(т("aw_nothing"))
                } else {
                    сеткаМарок(найденныеМарки)
                }
            }
        }
    }

    private var чистыйПоиск: String { поиск.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    private var найденныеМарки: [String] {
        модель.маркиАвто.filter { $0.lowercased().contains(чистыйПоиск) }
    }

    /// «Популярные» сверху, дальше — группы справочника по порядку сайта.
    private var группы: [ГруппаМарок] {
        var поНижнему: [String: String] = [:]
        for м in модель.маркиАвто where поНижнему[м.lowercased()] == nil { поНижнему[м.lowercased()] = м }
        let популярные = Self.популярные.compactMap { поНижнему[$0.lowercased()] }
        let подпись = т("aw_popular")
        var итог: [ГруппаМарок] = []
        if популярные.count >= 4 && !модель.группыМарок.contains(where: { $0.регион == подпись }) {
            итог.append(ГруппаМарок(регион: подпись, марки: популярные))
        }
        итог.append(contentsOf: модель.группыМарок)
        return итог
    }

    private func подписьГруппы(_ текст: String) -> some View {
        Text(текст.uppercased())
            .font(.system(size: 11, weight: .heavy))
            .kerning(0.4)
            .foregroundStyle(Theme.текстВторой)
            .padding(.top, 6)
            .accessibilityAddTraits(.isHeader)
    }

    private func сеткаМарок(_ марки: [String]) -> some View {
        LazyVGrid(columns: колонки, spacing: 8) {
            ForEach(марки, id: \.self) { м in
                ПлиткаМастераПодачи(м, буква: String(м.prefix(1)).uppercased(), логотипМарки: м, выбрана: марка == м) {
                    выбратьМарку(м)
                }
            }
        }
    }

    private func выбратьМарку(_ новая: String) {
        if новая != марка {
            марка = новая
            модельАвто = ""
            поколение = ""
            модели = []
        }
        ОткликСайта.выбор()
        перейти(.модель)
    }

    // MARK: Модель (_awStepModel)

    private var шагМодель: some View {
        VStack(alignment: .leading, spacing: 12) {
            ВопросМастераПодачи(т("aw_model"), пояснение: марка)
            if марка.isEmpty {
                ЗаметкаПодачи(т("aw_first_brand"), тон: .внимание)
            } else if моделиГрузятся {
                загрузка
            } else if модели.isEmpty {
                ЗаметкаПодачи(т("aw_models_none"), тон: .серый)
                СвоёЗначениеМастера(подпись: т("aw_model_other"), подсказка: т("aw_model_other_ph"), открыто: true) { своё in
                    выбратьМодель(своё)
                }
            } else {
                ПоискМастераПодачи(т("aw_model_search"), текст: $поиск)
                СвоёЗначениеМастера(подпись: т("aw_model_other"), подсказка: т("aw_model_other_ph")) { своё in
                    выбратьМодель(своё)
                }
                if найденныеМодели.isEmpty {
                    ПодсказкаПоля(т("aw_nothing"))
                } else {
                    /* Одним списком во всю ширину и без картинок (владелец: «без SVG… в один список, без разделения
                       на два»): название модели и годы выпуска под ним, по порядку справочника сайта. */
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(найденныеМодели) { м in
                            ПлиткаМастераПодачи(м.имя, пояснение: м.годыВыпуска(сейчас: т("aw_now")),
                                                выбрана: модельАвто == м.имя) {
                                выбратьМодель(м.имя)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Модели по поиску. Кузовом список не сужаем: у легковой кузов теперь ставит сама модель (models[].body).
    private var найденныеМодели: [МодельАвто] {
        let q = чистыйПоиск
        guard !q.isEmpty else { return модели }
        return модели.filter { $0.имя.lowercased().contains(q) }
    }

    private func выбратьМодель(_ имя: String) {
        if имя != модельАвто {
            модельАвто = имя
            поколение = ""
        }
        автоПоколение()
        обновитьКузов()
        ОткликСайта.выбор()
        /* Поколений больше одного — выбрать; одно встало само, нет ни одного — сразу «Об автомобиле». */
        перейти(поколенияМодели.count > 1 ? .поколение : .параметры)
    }

    @MainActor
    private func загрузитьМодели() async {
        let м = марка
        guard !м.isEmpty else {
            модели = []
            моделиГрузятся = false
            return
        }
        моделиГрузятся = true
        let список = await модель.моделиМарки(м)
        guard м == марка else { return }
        модели = список
        моделиГрузятся = false
        if !модельАвто.isEmpty {
            автоПоколение()
            обновитьКузов()
        }
        if шаг == .параметры { заготовить() }
    }

    // MARK: Кузов легковой по модели (models[].body)

    /// Подразделы кузова выбранной модели, которые есть в справочнике разделов под cars.
    private var кузоваМодели: [String] {
        guard легковая, let м = модели.first(where: { $0.имя == модельАвто }) else { return [] }
        var итог: [String] = []
        for к in м.кузов where к != "cars" && !итог.contains(к) {
            if модель.справочники.разделы[к] != nil && модель.справочники.внутри(к, ["cars"]) { итог.append(к) }
        }
        return итог
    }

    /// Чипы кузова на экране параметров: у модели несколько — они; нет данных — все кузова легковой; один — не
    /// спрашиваем (встал сам).
    private var вариантыКузова: [String] {
        guard легковая else { return [] }
        let свои = кузоваМодели
        if свои.count == 1 { return [] }
        if свои.count > 1 { return свои }
        return (модель.справочники.разделы["cars"]?.дети ?? []).filter { $0 != "cars" }
    }

    /// Один подраздел у модели — он и встанет; несколько — выбранный остаётся, только если он среди них. Раздел, с которым
    /// мастер открыли (правка, выбор в листе «Характеристик»), при той же модели не трогаем: его выбрал человек.
    private func обновитьКузов() {
        guard легковая else { return }
        if !исходныйКузов.isEmpty && кузов == исходныйКузов && модельАвто == исходнаяМодель { return }
        let свои = кузоваМодели
        if свои.count == 1 {
            кузов = свои[0]
        } else if свои.count > 1 && !свои.contains(кузов) {
            кузов = ""
        }
    }

    // MARK: Поколение (_awStepGen)

    private var поколенияМодели: [ПоколениеАвто] {
        модели.first(where: { $0.имя == модельАвто })?.поколения ?? []
    }

    private var выбранноеПоколение: ПоколениеАвто? {
        поколенияМодели.first(where: { $0.имя == поколение })
    }

    private var текущийГод: Int { Calendar.current.component(.year, from: Date()) }

    private var шагПоколение: some View {
        let гены = поколенияМодели
        let отрезок = отрезокЛет(гены)
        return VStack(alignment: .leading, spacing: 12) {
            ВопросМастераПодачи(т("aw_gen"), пояснение: заголовок)
            if гены.isEmpty {
                ЗаметкаПодачи(т("aw_gens_none"), тон: .серый)
            } else {
                LazyVGrid(columns: колонки, spacing: 8) {
                    ForEach(Array(гены.enumerated()), id: \.element.id) { пара in
                        let п = пара.element
                        let годы = годыПоколения(п)
                        let доли = долиНаШкале(п, отрезок)
                        ПлиткаПоколенияАвто(годы: годы.isEmpty ? п.имя : годы, код: годы.isEmpty ? "" : п.имя,
                                            с: доли.с, по: доли.по, выбрана: поколение == п.имя) {
                            выбратьПоколение(п)
                        }
                        .появлениеАвто(пара.offset)
                    }
                }
                ПодсказкаПоля(тп("ap_gen_hint"))
            }
        }
    }

    private func годыПоколения(_ п: ПоколениеАвто) -> String {
        guard п.с > 0 else { return "" }
        return String(п.с) + "–" + (п.по > 0 ? String(п.по) : т("aw_now"))
    }

    /// Все годы модели: от начала самого старого поколения до конца самого нового (идёт — до сих пор).
    private func отрезокЛет(_ гены: [ПоколениеАвто]) -> ClosedRange<Int> {
        let сейчас = текущийГод
        let начала = гены.map(\.с).filter { $0 > 0 }
        let концы = гены.filter { $0.с > 0 }.map { $0.по > 0 ? $0.по : сейчас }
        let от = начала.min() ?? сейчас
        let до = max(от, концы.max() ?? от)
        return от...до
    }

    /// Доли поколения на шкале модели (0…1); лет нет или шкала в один год — во всю ширину.
    private func долиНаШкале(_ п: ПоколениеАвто, _ отрезок: ClosedRange<Int>) -> (с: CGFloat, по: CGFloat) {
        let длина = отрезок.upperBound - отрезок.lowerBound
        guard п.с > 0, длина > 0 else { return (0, 1) }
        let конец = п.по > 0 ? п.по : текущийГод
        let с = CGFloat(min(max(п.с, отрезок.lowerBound), отрезок.upperBound) - отрезок.lowerBound) / CGFloat(длина)
        let по = CGFloat(min(max(конец, отрезок.lowerBound), отрезок.upperBound) - отрезок.lowerBound) / CGFloat(длина)
        return (с, max(с, по))
    }

    /// Одно поколение — выбрано само, шага «Поколение» нет (_awStepGen: 1 === n.length); в форме поколение, которого у
    /// модели нет (справочник переименовал), — тоже заменяется. Год не снимается: справочник мог отстать (2024 у
    /// поколения 2018–2023), а шага, где это было бы видно, нет.
    private func автоПоколение() {
        let гены = поколенияМодели
        if гены.count == 1 && поколение != гены[0].имя { поколение = гены[0].имя }
    }

    /// Плитку нажали: год вне лет поколения снимается — заново выбирается чипом лет поколения на экране параметров.
    private func выбратьПоколение(_ п: ПоколениеАвто) {
        поколение = п.имя
        if let г = Int(год), п.с > 0 {
            let до = п.по > 0 ? п.по : текущийГод
            if г < п.с || г > до { год = "" }
        }
        ОткликСайта.выбор()
        перейти(.параметры)
    }

    // MARK: Об автомобиле (_awStepNums и _awStepGearFuel одним экраном)

    private var этоЭлектро: Bool { топливо == Self.электро }

    /// «Toyota Camry · XV70» — под вопросом экрана.
    private var подзаголовок: String {
        поколение.isEmpty ? заголовок : заголовок + " · " + поколение
    }

    /// Годы выбора — новые первыми: годы поколения, без него — текущий … 1960. Год формы вне лет поколения (справочник
    /// отстал) — тоже среди них, на своём месте: его видно и можно оставить. Берётся год формы, а не текущий выбор, —
    /// список не меняется под пальцем.
    private var годыВыбора: [Int] {
        let сейчас = текущийГод
        if let п = выбранноеПоколение, п.с > 0 {
            let до = max(п.с, min(п.по > 0 ? п.по : сейчас, сейчас + 1))
            var итог = Array((п.с...до).reversed())
            if let г = Int(исходныйГод), г >= Self.первыйГод, г <= сейчас + 1, !итог.contains(г) {
                итог.append(г)
                итог.sort(by: >)
            }
            return итог
        }
        return Array((Self.первыйГод...max(Self.первыйГод, сейчас)).reversed())
    }

    /// Где стоит лента, пока год не выбран: машине лет десять.
    private var прикидкаГода: Int { текущийГод - 10 }

    /// Где стоит бледная ручка пробега: ~17 000 км на год возраста; года нет — 100 тыс.
    private var прикидкаПробега: Int {
        guard let г = Int(год), г > 1900, г <= текущийГод else { return 100_000 }
        return min(РегуляторПробега.предел, (текущийГод - г) * 17_000)
    }

    /// Объёмы поколения «1.6» (gens[].eng) по возрастанию, без повторов.
    private var объёмыПоколения: [String] {
        var итог: [String] = []
        for л in (выбранноеПоколение?.объёмы ?? []).sorted() {
            let строка = ВыборОбъёмаАвто.литры(л)
            if !итог.contains(строка) { итог.append(строка) }
        }
        return итог
    }

    /// Чипы объёма: объёмы поколения; без них у легковой — ходовые; у прочего транспорта без данных — блока нет.
    private var вариантыОбъёма: [String] {
        let свои = объёмыПоколения
        if !свои.isEmpty { return свои }
        return легковая ? Self.ходовыеОбъёмы : []
    }

    /// Топливо и коробка — у легковой всегда, у прочего транспорта — только когда их знает поколение.
    private var показатьТопливо: Bool { легковая || !(выбранноеПоколение?.топлива.isEmpty ?? true) }
    private var показатьКоробку: Bool { легковая || !(выбранноеПоколение?.коробки.isEmpty ?? true) }

    private var шагПараметры: some View {
        VStack(alignment: .leading, spacing: 12) {
            ВопросМастераПодачи(тп(легковая ? "ap_title" : "ap_title_other"), пояснение: подзаголовок)
            блокГода
            БлокПараметраАвто(т("aw_mileage"), значок: "speedometer", обязательно: легковая, номер: 1) {
                РегуляторПробега(пробег: $пробег, прикидка: прикидкаПробега)
            }
            if показатьТопливо {
                БлокПараметраАвто(т("aw_fuel"), значок: "fuelpump", номер: 2) {
                    ВыборСловаАвто(значение: топливо, все: Self.топлива, свои: выбранноеПоколение?.топлива ?? []) { новое in
                        выбратьТопливо(новое)
                    }
                }
            }
            if !вариантыОбъёма.isEmpty { блокОбъёма }
            if показатьКоробку {
                БлокПараметраАвто(т("aw_gear"), значок: "gearshape.2", номер: 4) {
                    ВыборСловаАвто(значение: коробка, все: Self.коробки, свои: выбранноеПоколение?.коробки ?? []) { новое in
                        коробка = новое
                    }
                }
            }
            if !вариантыКузова.isEmpty { блокКузова }
        }
        .animation(ДвижениеСайта.смена, value: этоЭлектро)
    }

    /// Год: поколение известно и лет немного — чипами; иначе — лентой (годы поколения или текущий … 1960).
    private var блокГода: some View {
        let п = выбранноеПоколение
        let годы = годыВыбора
        return БлокПараметраАвто(т("aw_year"), значок: "calendar", значение: год, обязательно: легковая, номер: 0) {
            if п != nil && годы.count <= 16 {
                ЧипыЛетАвто(годы: годы, выбран: год) { г in
                    выбратьГод(г)
                }
            } else {
                ЛентаГодовАвто(год: $год, годы: годы, прикидка: прикидкаГода)
                if год.isEmpty {
                    ПодсказкаПоля(тп("ap_year_tape"))
                }
            }
            if let п, п.с > 0 {
                ПодсказкаПоля(String(format: тп("ap_gen_years"), годыПоколения(п)))
            }
        }
    }

    /// Объём; у электромобиля вместо него — плашка «объём двигателя не нужен».
    @ViewBuilder
    private var блокОбъёма: some View {
        if этоЭлектро {
            ЗаметкаПодачи(тп("ap_ev"), тон: .хорошо, значок: "bolt.fill")
                .transition(AnyTransition.opacity.combined(with: AnyTransition.scale(scale: 0.97)))
        } else {
            БлокПараметраАвто(тп("ap_engine"), значок: "engine.combustion", номер: 3) {
                ВыборОбъёмаАвто(объём: $объём, варианты: вариантыОбъёма, лентой: объёмыПоколения.isEmpty)
            }
            .transition(.opacity)
        }
    }

    /// Кузов легковой чипом — когда модель не назвала его одним (несколько или нет данных); без выбора — cars.
    private var блокКузова: some View {
        БлокПараметраАвто(т("aw_body"), значок: "car", необязательно: true, номер: 5) {
            ПотокЧипов(зазор: 8) {
                ForEach(вариантыКузова, id: \.self) { к in
                    ЧипПодачи(имяРаздела(к), выбран: кузов == к) {
                        кузов = кузов == к ? "" : к
                        ОткликСайта.выбор()
                    }
                }
            }
        }
    }

    private func выбратьГод(_ г: Int) {
        guard год != String(г) else { return }
        год = String(г)
        ОткликСайта.выбор()
    }

    /// Топливо; «Электро» — объём не нужен (очищен, блок спрятан), коробка, если пустая, — «Автомат».
    private func выбратьТопливо(_ новое: String) {
        топливо = новое
        if новое == Self.электро {
            объём = ""
            if коробка.isEmpty { коробка = Self.автомат }
        }
    }

    /**
     Отметить заранее — один раз на марку, модель и поколение: единственный вариант поколения в gens[].fuel, gear и eng
     (если поле пустое); о топливе данных нет — электромобиль по марке и модели (ЭлектроАвто). Снятое потом не
     возвращается. Машина другая — отмеченное раньше само и не тронутое человеком снимается: Tesla → Camry не остаётся
     «Электро» без объёма. Пока модели грузятся — ждём: данные сервера важнее догадки.
     */
    private func заготовить() {
        guard !моделиГрузятся else { return }
        let ключ = [марка, модельАвто, поколение].joined(separator: "|")
        guard ключ != заготовлено else { return }
        заготовлено = ключ
        if автоОтмечено["топливо"] == топливо { топливо = "" }
        if автоОтмечено["коробка"] == коробка { коробка = "" }
        if автоОтмечено["объём"] == объём { объём = "" }
        var отмечено: [String: String] = [:]
        let п = выбранноеПоколение
        if let п {
            if топливо.isEmpty && п.топлива.count == 1 {
                топливо = п.топлива[0]
                отмечено["топливо"] = топливо
            }
            if коробка.isEmpty && п.коробки.count == 1 {
                коробка = п.коробки[0]
                отмечено["коробка"] = коробка
            }
            if объём.isEmpty && п.объёмы.count == 1 {
                объём = ВыборОбъёмаАвто.литры(п.объёмы[0])
                отмечено["объём"] = объём
            }
        }
        if легковая && топливо.isEmpty && (п?.топлива.isEmpty ?? true)
            && ЭлектроАвто.электро(марка: марка, модель: модельАвто) {
            топливо = Self.электро
            отмечено["топливо"] = топливо
        }
        if этоЭлектро {
            объём = ""
            if коробка.isEmpty {
                коробка = Self.автомат
                отмечено["коробка"] = коробка
            }
        }
        автоОтмечено = отмечено
    }

    // MARK: Ход мастера

    private var загрузка: some View {
        HStack(spacing: 10) {
            SiteSpinner()
            Text(т("aw_loading"))
                .font(.system(size: 14))
                .foregroundStyle(Theme.текстВторой)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
    }

    /// _aw2SyncNext: марка обязательна; поколение — если их у модели несколько; у легковой — ещё год и пробег.
    private var можноДалее: Bool {
        switch шаг {
        case .марка:
            return !марка.isEmpty
        case .поколение:
            /* Поколение формы, которого у модели нет (старое имя), не годится — выбрать плиткой. */
            return поколенияМодели.isEmpty || выбранноеПоколение != nil
        case .параметры:
            guard !марка.isEmpty else { return false }
            guard легковая else { return true }
            return !год.trimmingCharacters(in: .whitespaces).isEmpty && !пробег.isEmpty
        case .кузов, .модель:
            return true
        }
    }

    private func перейти(_ новый: Шаг) {
        поиск = ""
        let куда = шаги.firstIndex(of: новый) ?? номер
        вперёд = куда >= номер
        if новый == .параметры {
            автоПоколение()
            обновитьКузов()
        }
        withAnimation(ДвижениеСайта.смена) { шаг = новый }
        if новый == .параметры { заготовить() }
    }

    private func назад() {
        let н = номер
        if н == 0 {
            закрыть()
        } else {
            перейти(шаги[н - 1])
        }
    }

    private func далее() {
        guard можноДалее else { return }
        let н = номер
        if н + 1 < шаги.count {
            перейти(шаги[н + 1])
        } else {
            применить()
        }
    }

    /// autoWizReset: всё заново с первого шага.
    private func сбросить() {
        кузов = ""
        марка = ""
        модельАвто = ""
        поколение = ""
        год = ""
        пробег = ""
        объём = ""
        коробка = ""
        топливо = ""
        модели = []
        заготовлено = ""
        автоОтмечено = [:]
        перейти(шаги.first ?? .марка)
    }

    @MainActor
    private func закрыть() {
        модель.мастер = nil
    }

    /**
     autoWizApply: у легковой сначала подраздел кузова (от модели или чипом, без него — cars; в правке — только если
     кузов в мастере поменялся), потом марка, модель, поколение — всегда; год, пробег, объём, коробка, топливо — если
     заданы; у электромобиля объём очищается.
     */
    @MainActor
    private func применить() {
        if легковая && (!модель.правка || кузов != исходныйКузов) {
            let нужный = кузов.isEmpty ? "cars" : кузов
            if модель.форма.раздел != нужный && модель.справочники.разделы[нужный] != nil {
                модель.выбратьРаздел(нужный)
            }
        }
        var ф = модель.форма
        ф.бренд = марка
        ф.модель = модельАвто
        ф.поколение = поколение
        if !год.isEmpty { ф.year = год }
        if !пробег.isEmpty { ф.ram = пробег }
        if этоЭлектро {
            ф.storage = ""
        } else if !объём.isEmpty {
            ф.storage = ВыборОбъёмаАвто.ровно(объём)
        }
        if !коробка.isEmpty { ф.cpu = коробка }
        if !топливо.isEmpty { ф.gpu = топливо }
        модель.форма = ф
        модель.моделиАвто = модели
        модель.мастер = nil
        ОткликСайта.успех()
        модель.показать(т("aw_saved"))
    }
}

// MARK: - Мастер объекта недвижимости (_rw2)

/**
 Мастер объекта (realtyWizOpen сайта): 1) сделка и вид объекта, 2) параметры (числа, чипы кроме срока и «кто
 размещает», списки кроме документов), 3) условия (переключатели, документы, «кто размещает», срок аренды),
 4) проверка. Обязательные поля (req) держат «Далее» (_rw2SyncNext). «Сохранить» — REALTY_DATA в форму: сдаю —
 аренда с периодом по сроку, название и описание собираются сами (realtyAutofill).
 */
struct МастерНедвижимостиВид: View {
    @ObservedObject var модель: ПодачаМодель

    @State private var шаг: Int
    @State private var сделка: String
    @State private var вид: String
    @State private var значения: [String: String]
    @State private var флаги: [String: Bool]
    @State private var список: СписокВыбора? = nil

    init(модель: ПодачаМодель, форма: ФормаПодачи, сШага: Int) {
        self.модель = модель
        let готово = !форма.сделка.isEmpty && !форма.вид.isEmpty
        _шаг = State(initialValue: готово ? min(max(0, сШага), 3) : 0)
        _сделка = State(initialValue: форма.сделка)
        _вид = State(initialValue: форма.вид)
        var значения = форма.недвижимость
        if значения["owner"] == nil { значения["owner"] = "owner" }
        _значения = State(initialValue: значения)
        _флаги = State(initialValue: форма.флагиНедвижимости)
    }

    private func т(_ ключ: String) -> String { МастерПодачиText.т(ключ) }

    private static let виды = ["apartment", "house", "commercial", "land"]
    /// _ASTART_REALTY: вид объекта → раздел каталога.
    private static let разделы: [String: String] = ["apartment": "apartments", "house": "houses",
                                                    "commercial": "commercial-realty", "land": "land"]

    private let колонки = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        ОкноМастераПодачи(значок: значокВида(вид), заголовок: заголовок, шаг: шаг, всего: 4,
                          далееПодпись: т(шаг >= 3 ? "m_save" : "m_next"), можноДалее: можноДалее,
                          подсказкаДалее: шаг == 0 ? nil : т("rw_req"),
                          закрыть: { закрыть() }, назад: { назад() }, далее: { далее() }) {
            содержимое
        }
        .sheet(item: $список) { с in
            ЛистВыбора(список: с)
        }
    }

    private var заголовок: String {
        guard !вид.isEmpty else { return т("rw_title") }
        let хвост = сделка == "rent" ? " · " + т("rd_rent_l") : (сделка == "sale" ? " · " + т("rd_sale_l") : "")
        return т("rk_" + вид) + хвост
    }

    private func значокВида(_ в: String) -> String {
        switch в {
        case "house": return "house"
        case "commercial": return "building"
        case "land": return "map"
        default: return "building.2"
        }
    }

    @ViewBuilder
    private var содержимое: some View {
        switch шаг {
        case 0: шагСделка
        case 1: шагПолей(1)
        case 2: шагПолей(2)
        default: шагПроверка
        }
    }

    // MARK: Сделка и вид (_rw2Step0)

    private var шагСделка: some View {
        VStack(alignment: .leading, spacing: 14) {
            ВопросМастераПодачи(т("rw_what_q"), пояснение: т("rw_what_s"))
            ПодписьПоля(т("rw_deal_l"), мелкая: true)
            LazyVGrid(columns: колонки, spacing: 8) {
                ПлиткаМастераПодачи(т("rw_sale"), пояснение: т("rw_sale_s"), значок: "house", выбрана: сделка == "sale") {
                    выбратьСделку("sale")
                }
                ПлиткаМастераПодачи(т("rw_rent"), пояснение: т("rw_rent_s"), значок: "key", выбрана: сделка == "rent") {
                    выбратьСделку("rent")
                }
            }
            ПодписьПоля(т("rw_kind_l"), мелкая: true)
            LazyVGrid(columns: колонки, spacing: 8) {
                ForEach(Self.виды, id: \.self) { в in
                    ПлиткаМастераПодачи(т("rk_" + в), значок: значокВида(в), выбрана: вид == в) {
                        выбратьВид(в)
                    }
                }
            }
        }
    }

    private func выбратьСделку(_ новая: String) {
        guard новая != сделка else { return }
        сделка = новая
        /* Поля у продажи и аренды разные — лишние значения не тянем. */
        значения = ["owner": значения["owner"] ?? "owner"]
        флаги = [:]
        ОткликСайта.выбор()
    }

    private func выбратьВид(_ новый: String) {
        guard новый != вид else { return }
        вид = новый
        значения = ["owner": значения["owner"] ?? "owner"]
        флаги = [:]
        ОткликСайта.выбор()
    }

    // MARK: Поля (_rw2Step1 / _rw2Step2)

    private var поля: [ПолеМастера] {
        guard !сделка.isEmpty, !вид.isEmpty else { return [] }
        return модель.справочники.недвижимость[сделка]?[вид] ?? []
    }

    /// _rw2FieldsOf: 1 — параметры, 2 — условия.
    private func поляГруппы(_ группа: Int) -> [ПолеМастера] {
        поля.filter { п in
            let условие = п.вид == "toggle" || п.id == "docs" || п.id == "owner" || п.id == "term"
            return группа == 2 ? условие : !условие
        }
    }

    private func шагПолей(_ группа: Int) -> some View {
        let свои = поляГруппы(группа)
        let вопрос = группа == 1 ? т("rw_params_q") : т(сделка == "rent" ? "rw_cond_rent" : "rw_cond_sale")
        let пояснение = группа == 1 ? т("rw_params_s") : т(сделка == "rent" ? "rw_cond_rent_s" : "rw_cond_sale_s")
        return VStack(alignment: .leading, spacing: 14) {
            ВопросМастераПодачи(вопрос, пояснение: пояснение)
            if свои.isEmpty {
                ЗаметкаПодачи(т("rw_none"), тон: .серый)
            } else {
                ForEach(свои) { поле in
                    ПолеМастераВид(поле: поле, значение: значение(поле.id), флаг: флаг(поле.id), варианты: поле.варианты,
                                   показатьСписок: { с in список = с })
                }
            }
        }
    }

    private func значение(_ ключ: String) -> Binding<String> {
        let связь = $значения
        return Binding(get: { связь.wrappedValue[ключ] ?? "" }, set: { новое in
            if новое.isEmpty {
                связь.wrappedValue.removeValue(forKey: ключ)
            } else {
                связь.wrappedValue[ключ] = новое
            }
        })
    }

    private func флаг(_ ключ: String) -> Binding<Bool> {
        let связь = $флаги
        return Binding(get: { связь.wrappedValue[ключ] ?? false }, set: { новое in
            связь.wrappedValue[ключ] = новое
        })
    }

    // MARK: Проверка (_rw2Step3)

    private var шагПроверка: some View {
        VStack(alignment: .leading, spacing: 14) {
            ВопросМастераПодачи(т("rw_sum_q"), пояснение: т("rw_sum_s"))
            VStack(spacing: 0) {
                строка(т("rw_deal"), т(сделка == "rent" ? "rd_rent" : "rd_sale"))
                строка(т("rw_obj"), вид.isEmpty ? "—" : т("rk_" + вид))
                ForEach(заполненные, id: \.0) { пара in
                    строка(пара.0, пара.1)
                }
            }
            .background(КраскаПодачи.карточка, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                    .strokeBorder(КраскаПодачи.линия, lineWidth: 1)
            }
        }
    }

    /// Заполненные поля: подпись и показ (вариант, «да» у переключателя, число с единицей).
    private var заполненные: [(String, String)] {
        var итог: [(String, String)] = []
        for п in поля {
            if п.вид == "toggle" {
                if флаги[п.id] == true { итог.append((п.подпись, т("rw_yes"))) }
                continue
            }
            let з = значения[п.id] ?? ""
            guard !з.isEmpty else { continue }
            let показ = п.варианты.first(where: { $0.ключ == з })?.подпись ?? (з + (п.единица.isEmpty ? "" : " " + п.единица))
            итог.append((п.подпись, показ))
        }
        return итог
    }

    private func строка(_ ключ: String, _ значение: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(ключ)
                .font(.system(size: 14))
                .foregroundStyle(Theme.текстВторой)
            Spacer(minLength: 8)
            Text(значение)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(КраскаПодачи.текст)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) {
            Rectangle().fill(КраскаПодачи.линия).frame(height: 1).padding(.leading, 14)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Ход мастера

    private var можноДалее: Bool {
        switch шаг {
        case 0:
            return !сделка.isEmpty && !вид.isEmpty
        case 1, 2:
            return поляГруппы(шаг).filter { $0.обязательно && $0.вид != "toggle" }
                .allSatisfy { !(значения[$0.id] ?? "").isEmpty }
        default:
            return true
        }
    }

    private func назад() {
        if шаг == 0 {
            закрыть()
        } else {
            withAnimation(ДвижениеСайта.смена) { шаг -= 1 }
        }
    }

    private func далее() {
        guard можноДалее else { return }
        if шаг < 3 {
            withAnimation(ДвижениеСайта.смена) { шаг += 1 }
        } else {
            сохранить()
        }
    }

    @MainActor
    private func закрыть() {
        модель.мастер = nil
    }

    /// realtyWizNext на последнем шаге: REALTY_DATA, аренда по сделке, период по сроку, раздел по виду объекта.
    @MainActor
    private func сохранить() {
        if let раздел = Self.разделы[вид], модель.видНедвижимости(модель.форма.раздел) != вид
            || !модель.справочники.внутри(модель.форма.раздел, ["realty"]) {
            if модель.справочники.разделы[раздел] != nil { модель.выбратьРаздел(раздел) }
        }
        var ф = модель.форма
        ф.тип = "realty"
        ф.сделка = сделка
        ф.вид = вид
        ф.недвижимость = значения
        ф.флагиНедвижимости = флаги.filter { $0.value }
        ф.аренда = сделка == "rent"
        if сделка == "rent" { ф.период = значения["term"] == "daily" ? "day" : "month" }
        модель.форма = ф
        модель.мастер = nil
        ОткликСайта.успех()
        модель.показать(т("rw_saved"))
    }
}

// MARK: - Карточки входа в мастера (#aw2-entry, #rw2-entry)

/// Кнопка-карточка .rw2-entry: значок, «Параметры автомобиля» / «Указать параметры…», сводка и «›». Незаполненная —
/// зелёный пунктир (зовёт заполнить), заполненная — мятная; ошибка — красная кромка.
struct ВходМастераПодачи: View {
    let значок: String
    let заголовок: String
    let подпись: String
    let заполнено: Bool
    let ошибка: Bool
    let действие: () -> Void

    init(значок: String, заголовок: String, подпись: String, заполнено: Bool, ошибка: Bool = false,
         действие: @escaping () -> Void) {
        self.значок = значок
        self.заголовок = заголовок
        self.подпись = подпись
        self.заполнено = заполнено
        self.ошибка = ошибка
        self.действие = действие
    }

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
        return Button(action: действие) {
            HStack(spacing: 12) {
                Image(systemName: значок)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(заполнено ? Color.white : КраскаПодачи.хорошоТекст)
                    .frame(width: 40, height: 40)
                    .background(заполнено ? КраскаПодачи.хорошоТекст : КраскаПодачи.хорошоФон,
                                in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(заголовок)
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(КраскаПодачи.текст)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(подпись)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.текстВторой)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(КраскаПодачи.хорошоТекст)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(заполнено ? КраскаПодачи.хорошоФон : КраскаПодачи.карточка, in: форма)
            .overlay {
                if ошибка {
                    форма.strokeBorder(Theme.ценаСкидка, lineWidth: 2)
                } else if заполнено {
                    форма.strokeBorder(КраскаПодачи.акцентТекст.opacity(0.35), lineWidth: 1)
                } else {
                    форма.strokeBorder(КраскаПодачи.хорошоТекст, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                }
            }
            .contentShape(форма)
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
    }
}

extension ПодачаМодель {
    /// autoWizSync: «Toyota Camry · 2019 г. · 85 000 км» — что уже выбрано в мастере авто.
    var сводкаАвто: String {
        let ф = форма
        let т = МастерПодачиText.т
        var части: [String] = []
        let имя = [ф.бренд, ф.модель].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !имя.isEmpty { части.append(имя.joined(separator: " ")) }
        if !ф.поколение.isEmpty { части.append(ф.поколение) }
        if !ф.year.isEmpty {
            let г = т("aw_yr")
            части.append(г.isEmpty ? ф.year : ф.year + " " + г)
        }
        if let пробег = Int(ф.ram), пробег >= 0, !ф.ram.isEmpty {
            части.append(Self.деньги(пробег) + " " + т("aw_km"))
        }
        return части.joined(separator: " · ")
    }

    /// _rwEntryHTML: «Квартира · Продажа» и «2-комнатная квартира, 54 м²» — что выбрано в мастере объекта.
    var сводкаНедвижимости: (заголовок: String, подпись: String) {
        let т = МастерПодачиText.т
        guard !форма.вид.isEmpty else { return (т("rw_entry_new"), т("rw_entry_new_s")) }
        let сделка = форма.сделка == "rent" ? т("rd_rent") : т("rd_sale")
        let подпись = названиеНедвижимости()
        return (т("rk_" + форма.вид) + " · " + сделка, подпись.isEmpty ? т("rw_entry_saved") : подпись)
    }

    /// Мастер авто по карточке параметров (без шага «Кузов»).
    func открытьМастерАвто() {
        мастер = .авто(кузов: false)
    }

    /// Мастер объекта по карточке параметров: с первого шага, если сделки или вида нет.
    func открытьМастерНедвижимости() {
        мастерНедвижимостиБыл = true
        мастер = .недвижимость(сШага: форма.сделка.isEmpty || форма.вид.isEmpty ? 0 : 1)
    }
}
