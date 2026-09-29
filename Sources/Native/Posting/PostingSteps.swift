import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

/**
 ПОДАЧА — РАМКА ШАГОВ И ШАГИ «ФОТО», «ДАННЫЕ ТОВАРА», «ХАРАКТЕРИСТИКИ», ЭТАП 42 (владелец 26.09.2026) + TestFlight 1.10
 («редактирование и добавление — дизайн улучшить, более понятнее и проще»).

 Рамка — addStepsSync сайта в новом виде: сверху «Шаг 2 из 5 · Данные товара» и тонкая полоса хода (считаются только
 видимые шаги — пустые пропускаются, как у сайта), в правке ещё и ряд шагов с точкой у изменённых. Внизу всегда видны
 «‹ Назад» и одна главная зелёная кнопка: «Далее →», на «Проверке» — «Выставить на продажу» (у аренды — «Сдать в
 аренду»), в правке — «Сохранить» на каждом шаге. Когда открыта клавиатура, низ становится панелью «↑ ↓ Готово», а поле
 само прокручивается в видимую часть. Ошибки проверок — красной строкой под своим полем.

 Шаг «Фото» — #photo-ecard: большая плитка «Добавить фото» (галерея), «Камера», сетка с переносом пальцем, первое —
 обложка, «✕» на плитке, кольцо загрузки; когда фото готовы — «Фото готовы — распознать?» (только по нажатию).
 «Данные» — #add-card-data: название, раздел (лист с поиском вместо трёх списков), бренд, описание.
 «Характеристики» — E_SPECS раздела, мастер недвижимости (REALTY_FIELDS), авто (/api/auto_models.php), запчастей
 (PARTS_FIELDS, /api/parts_types.php), VIN. Выбор — сегментом (2–4 коротких варианта), меню (средние списки), листом с
 поиском (длинные), числа — числовым полем.
 */
struct ШагиПодачи: View {
    @ObservedObject var модель: ПодачаМодель
    let открытьАдрес: (String) -> Void
    let закрыть: () -> Void
    @FocusState private var фокус: String?

    init(модель: ПодачаМодель, открытьАдрес: @escaping (String) -> Void, закрыть: @escaping () -> Void) {
        self.модель = модель
        self.открытьАдрес = открытьАдрес
        self.закрыть = закрыть
    }

    private func т(_ ключ: String) -> String { ПодачаText.т(ключ) }

    var body: some View {
        ScrollViewReader { прокрутка in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Color.clear
                        .frame(height: 0)
                        .id("верх")
                    ГеройПодачи(правка: модель.правка, закрыть: закрыть)
                    /* Плашка eGov («без верификации не выйдет на витрину») — не на шагах, а после публикации
                       (окно итога: «eGov — 1 минута»), владелец, обход новичком. */
                    if !модель.правка && !модель.быстрый { полосаТипа }
                    полоса
                        .padding(.top, 2)
                    if модель.быстрый && !модель.правка {
                        ПроверкаКамерыПодачи(модель: модель, фокус: $фокус, открытьАдрес: открытьАдрес)
                    } else {
                        шаг
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .submitLabel(.next)
            .onSubmit { перейтиКПолю(1) }
            .onChange(of: фокус) { _, ключ in
                guard let ключ else { return }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    withAnimation(ДвижениеСайта.прокрутка) { прокрутка.scrollTo(ключ, anchor: .center) }
                }
            }
            .onChange(of: модель.шаг) { _, _ in
                фокус = nil
                withAnimation(ДвижениеСайта.прокрутка) { прокрутка.scrollTo("верх", anchor: .top) }
            }
            .onChange(of: модель.ошибкиПолей) { было, стало in
                /* Новая ошибка — показать её поле (после перехода на нужный шаг). */
                guard let ключ = стало.keys.first(where: { было[$0] == nil }) else { return }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    withAnimation(ДвижениеСайта.прокрутка) { прокрутка.scrollTo(ключ, anchor: .center) }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { низ }
        .fullScreenCover(item: $модель.мастер) { м in
            мастер(м)
        }
    }

    /// Мастера поверх шагов: авто (кузов — дети раздела со старта) и объект недвижимости.
    @ViewBuilder
    private func мастер(_ м: МастерПодачи) -> some View {
        switch м {
        case .авто(let кузов):
            МастерАвтоВид(модель: модель, форма: модель.форма,
                          кузова: модель.справочники.разделы[модель.форма.раздел]?.дети ?? [], сКузовом: кузов)
        case .недвижимость(let сШага):
            МастерНедвижимостиВид(модель: модель, форма: модель.форма, сШага: сШага)
        }
    }

    // MARK: Шапка шага

    /**
     .add-steps: полоса из сегментов во всю ширину — по одному на каждый шаг, который есть у этого вида объявления
     (пустые шаги пропускаются, как у сайта), пройденные — зелёные; под ней «Фото  1 / 6»; в правке — ряд шагов.
     */
    private var полоса: some View {
        let номер = модель.номерШага
        return VStack(alignment: .leading, spacing: 8) {
            ПолосаШаговПодачи(всего: номер.всего, текущий: номер.номер - 1)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(модель.названиеШага(модель.шаг))
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(КраскаПодачи.текст)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(String(номер.номер) + " / " + String(номер.всего))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.текстВторой)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            if модель.правка { полосаПравки }
        }
    }

    /// Правка: все шаги рядом — нажатие ведёт на шаг, точка — там что-то поменяли.
    private var полосаПравки: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(модель.видимыеШаги) { ш in
                    кнопкаШага(ш)
                }
            }
        }
    }

    private func кнопкаШага(_ ш: ШагПодачи) -> some View {
        let текущий = ш == модель.шаг
        let изменён = модель.изменён(ш)
        return Button {
            фокус = nil
            модель.перейти(к: ш)
        } label: {
            HStack(spacing: 5) {
                Text(модель.названиеШага(ш))
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)
                if изменён {
                    Circle()
                        .fill(Theme.золото)
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(текущий ? КраскаПодачи.хорошоТекст : Theme.текстВторой)
            .padding(.horizontal, 10)
            .frame(minHeight: 30)
            .background(текущий ? КраскаПодачи.хорошоФон : КраскаПодачи.карточка, in: Capsule())
            .overlay { Capsule().strokeBorder(текущий ? Color.clear : КраскаПодачи.линия, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(текущий ? .isSelected : [])
        .accessibilityValue(изменён ? т("edited") : "")
    }

    /// Полоса выбранного типа #aft-bar: значок, тип и подпись плитки, «Изменить» — на всех шагах.
    private var полосаТипа: some View {
        HStack(spacing: 12) {
            Image(systemName: значокТипа)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(КраскаПодачи.хорошоТекст)
                .frame(width: 34, height: 34)
                .background(КраскаПодачи.хорошоФон, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(названиеТипа)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(КраскаПодачи.текст)
                    .lineLimit(1)
                if let подпись = модель.форма.плиткаПодпись, !подпись.isEmpty {
                    Text(подпись)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Button { модель.сменитьТип() } label: {
                Text(т("change"))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(КраскаПодачи.текст)
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 28)
                    .overlay { Capsule().strokeBorder(КраскаПодачи.линия, lineWidth: 1) }
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(КраскаПодачи.карточка, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(КраскаПодачи.линия, lineWidth: 1)
        }
        .shadow(color: КраскаПодачи.тень, radius: 6, y: 2)
    }

    private var названиеТипа: String {
        let раздел = модель.справочники.имя(модель.форма.раздел)
        if !модель.форма.плитка.isEmpty { return модель.форма.плитка }
        return раздел.isEmpty ? т("as_goods") : раздел
    }

    /// Значок .b-ic по корню раздела; раздел ещё не выбран — коробка.
    private var значокТипа: String {
        модель.корень.isEmpty ? "shippingbox" : ЗначокРазделаПодачи.символ(модель.корень)
    }

    @ViewBuilder
    private var шаг: some View {
        switch модель.шаг {
        case .фото: ШагФото(модель: модель, фокус: $фокус)
        case .данные: ШагДанные(модель: модель, фокус: $фокус)
        case .характеристики: ШагХарактеристики(модель: модель, фокус: $фокус)
        case .цена: ШагЦена(модель: модель, фокус: $фокус)
        case .адрес: ШагАдрес(модель: модель, фокус: $фокус)
        case .дополнительно: ШагДополнительно(модель: модель, фокус: $фокус, открытьАдрес: открытьАдрес)
        case .проверка: ШагПроверка(модель: модель, открытьАдрес: открытьАдрес)
        }
    }

    // MARK: Низ

    /// Низ всегда на экране (над полосой «домой»), на цвете страницы, как .add-stepnav: «Назад» и главная кнопка;
    /// с клавиатурой — «↑ ↓ Готово».
    private var низ: some View {
        Group {
            if фокус != nil {
                панельКлавиатуры
            } else {
                кнопкиШагов
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, фокус != nil ? 6 : 10)
        .background(КраскаПодачи.фон.ignoresSafeArea(edges: .bottom))
    }

    @ViewBuilder
    private var кнопкиШагов: some View {
        let быстро = модель.быстрый && !модель.правка
        let первый = модель.видимыеШаги.first == модель.шаг && !быстро
        let последний = модель.шаг == .проверка || быстро
        if !модель.правка && последний {
            /* #submit-btn во всю ширину, «Назад» — под ним. */
            VStack(spacing: 10) {
                КнопкаПодачи(кнопкаОтправки, занято: модель.отправляем) { модель.выставить() }
                if !первый {
                    КнопкаНазадПодачи { модель.назад() }
                }
            }
        } else {
            HStack(spacing: 10) {
                if !первый {
                    КнопкаНазадПодачи { модель.назад() }
                }
                if модель.правка {
                    if !последний {
                        КнопкаПодачиВторая(т("next")) { модель.далее() }
                    }
                    КнопкаПодачи(т(модель.отправляем ? "saving" : "save"), занято: модель.отправляем) { модель.сохранить() }
                } else {
                    КнопкаДалееПодачи(т("next")) { модель.далее() }
                }
            }
        }
    }

    private var кнопкаОтправки: String {
        if модель.отправляем { return т("sending") }
        let аренда = модель.форма.аренда && !модель.форма.тожеПродаю
        /* Короткий путь с камеры: «Опубликовать». */
        if модель.быстрый && !аренда { return т("pc_publish") + " →" }
        return т(модель.форма.аренда && !модель.форма.тожеПродаю ? "form_submit_rent" : "form_submit") + " →"
    }

    /// Над клавиатурой: предыдущее и следующее поле шага, «Готово» — убрать клавиатуру.
    private var панельКлавиатуры: some View {
        let поля = порядокПолей
        let место = фокус.flatMap { поля.firstIndex(of: $0) }
        let можноНазад = (место ?? 0) > 0
        let можноВперёд = место.map { $0 < поля.count - 1 } ?? false
        return HStack(spacing: 20) {
            Button {
                перейтиКПолю(-1)
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 36, height: 36)
            }
            .disabled(!можноНазад)
            .accessibilityLabel(т("kb_prev"))
            Button {
                перейтиКПолю(1)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 36, height: 36)
            }
            .disabled(!можноВперёд)
            .accessibilityLabel(т("kb_next"))
            Spacer(minLength: 0)
            Button(т("done")) { фокус = nil }
                .font(.system(size: 16, weight: .bold))
        }
        .foregroundStyle(Theme.акцент)
        .buttonStyle(.plain)
    }

    private func перейтиКПолю(_ сдвиг: Int) {
        let поля = порядокПолей
        guard let текущее = фокус, let место = поля.firstIndex(of: текущее) else {
            фокус = nil
            return
        }
        let новое = место + сдвиг
        фокус = (новое >= 0 && новое < поля.count) ? поля[новое] : nil
    }

    /// Поля ввода текущего шага сверху вниз — ключи те же, что у ФокусПоля.
    private var порядокПолей: [String] {
        let ф = модель.форма
        var п: [String] = []
        if модель.быстрый && !модель.правка {
            /* «Проверьте»: название, цена, описание, город и адрес — что из них на экране. */
            if модель.режим != .авто { п.append("title") }
            п.append(contentsOf: ["price", "desc", "city", "address"])
            return п
        }
        switch модель.шаг {
        case .данные:
            if модель.режим != .авто { п.append("title") }
            п.append("desc")
        case .характеристики:
            if модель.брендВиден && модель.бренды.isEmpty { п.append("brand") }
            switch модель.режим {
            case .авто:
                п.append(contentsOf: ["mileage", "engine"])
            case .недвижимость:
                for поле in модель.поляНедвижимости where поле.вид == "num" || поле.вид == "text" { п.append("rf_" + поле.id) }
            case .запчасти:
                for поле in модель.поляЗапчасти where поле.вид == "num" || поле.вид == "text" { п.append("pf_" + поле.id) }
            case .товар, .услуга, .работа:
                for поле in модель.рядыХарактеристик.flatMap({ $0 }) where поле.вводом {
                    п.append("sp_" + поле.поле)
                }
            }
            if модель.vinРазрешён { п.append("vin") }
        case .цена:
            п.append("price")
            if модель.арендаДоступна && ф.аренда {
                п.append(contentsOf: ["rate", "deposit"])
                if модель.режим != .недвижимость { п.append("kit") }
            }
            if модель.страница.состояние?.магазин == true && модель.режим == .товар { п.append("stock") }
        case .адрес:
            if модель.городВводом { п.append("city") }
            п.append("address")
        case .фото:
            if модель.режим == .услуга && !модель.услуга.направление.isEmpty {
                п.append(contentsOf: ["svc_do", "svc_inc", "svc_price", "svc_city"])
            }
        case .дополнительно, .проверка:
            break
        }
        return п
    }
}

// MARK: - Фото

struct ШагФото: View {
    @ObservedObject var модель: ПодачаМодель
    let фокус: FocusState<String?>.Binding
    @State private var выбор: [PhotosPickerItem] = []
    @State private var камера = false
    @State private var тащим: UUID? = nil
    /// Услуга: фото свёрнуто (у сайта «необязательно для услуги») — разворачивается «Добавить своё фото».
    @State private var фотоУслуги = false

    init(модель: ПодачаМодель, фокус: FocusState<String?>.Binding) {
        self.модель = модель
        self.фокус = фокус
    }

    private func т(_ ключ: String) -> String { ПодачаText.т(ключ) }

    /// Услуга (не правка): сначала мастер услуги, фото — по желанию.
    private var услуга: Bool { модель.режим == .услуга && !модель.правка }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !модель.правка { входМастера }
            if услуга { МастерУслугиВид(модель: модель, фокус: фокус) }
            if услуга && !модель.услуга.направление.isEmpty { ПостерУслугиПодачиВид(модель: модель) }
            if !услуга || фотоУслуги || !модель.плитки.isEmpty {
                карточкаФото
            } else {
                свёрнутоеФото
            }
            if модель.распознаваниеДоступно { блокИИ }
            if let статус = модель.статусИИ {
                ЗаметкаПодачи(статус, тон: модель.заполненоИИ ? .хорошо : .внимание, значок: "sparkles")
            }
        }
        .fullScreenCover(isPresented: $камера) {
            КамераПодачи(снято: { снимок in модель.принять(снимок: снимок) }, закрыть: { камера = false })
                .ignoresSafeArea()
        }
        .onChange(of: выбор) { _, новые in
            guard !новые.isEmpty else { return }
            let взятые = новые
            выбор = []
            Task { await модель.принять(взятые) }
        }
    }

    /// Авто и недвижимость: карточка параметров над фото (#aw2-entry / #rw2-entry) — сначала марка и модель.
    @ViewBuilder
    private var входМастера: some View {
        let тм = МастерПодачиText.т
        let есть = !модель.форма.бренд.trimmingCharacters(in: .whitespaces).isEmpty
        let сводка = модель.сводкаНедвижимости
        switch модель.режим {
        case .авто:
            VStack(alignment: .leading, spacing: 6) {
                ВходМастераПодачи(значок: "car", заголовок: тм(есть ? "aw_entry_t" : "aw_entry_new"),
                                  подпись: есть ? модель.сводкаАвто : тм("aw_entry_s"), заполнено: есть,
                                  ошибка: модель.ошибка("auto") != nil) {
                    модель.открытьМастерАвто()
                }
                СтрокаОшибки(модель.ошибка("auto"))
            }
            .id("auto")
        case .недвижимость:
            ВходМастераПодачи(значок: "house", заголовок: сводка.заголовок, подпись: сводка.подпись,
                              заполнено: !модель.форма.вид.isEmpty && !модель.форма.недвижимость.isEmpty) {
                модель.открытьМастерНедвижимости()
            }
        case .товар, .запчасти, .услуга, .работа:
            EmptyView()
        }
    }

    /// #photo-ecard: зона «Добавьте фото» или сетка, под ними — план съёмки сайта (что и как снять).
    private var карточкаФото: some View {
        КарточкаПодачи(т("step_photo"), подпись: подпись, значок: "camera") {
            if модель.плитки.isEmpty {
                зона
            } else {
                сетка
                if КамераПодачи.есть && модель.местоФото > 0 { кнопкаКамеры }
            }
            if модель.местоФото == 0 {
                ПодсказкаПоля(String(format: т("photo_cap_full"), модель.лимитФото))
            }
            if let план = модель.планСъёмки {
                ПланСъёмкиВид(план: план, снято: модель.плитки.count)
            }
        }
    }

    /// Фото услуги свёрнуто: «Фото · необязательно для услуги» и «Добавить своё фото».
    private var свёрнутоеФото: some View {
        Button {
            withAnimation(ДвижениеСайта.смена) { фотоУслуги = true }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "camera")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(КраскаПодачи.хорошоТекст)
                    .frame(width: 34, height: 34)
                    .background(КраскаПодачи.хорошоФон, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(МастерПодачиText.т("svc_photo_add"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(КраскаПодачи.текст)
                    Text(т("step_photo") + " · " + МастерПодачиText.т("svc_photo_opt"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                }
                Spacer(minLength: 0)
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(КраскаПодачи.хорошоТекст)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(КраскаПодачи.карточка, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                    .strokeBorder(КраскаПодачи.линия, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
    }

    /// Пусто — подсказки нет (она в зоне); есть фото — «2 из 5 фото · первое — обложка, перетащите…».
    private var подпись: String? {
        if модель.плитки.isEmpty { return nil }
        let счёт = String(format: т("photo_count"), модель.плитки.count, модель.лимитФото)
        return счёт + " · " + т("photo_order_hint")
    }

    /**
     .photo-zone: пунктир --line 2 px на --surf2, значок в мятном круге, «Добавьте фото», «Галерея» (--g) и «Камера»
     (светло-зелёная, как вторичные кнопки кабинета — не синяя), «до N фото · jpg/png/webp». Зона высокая — главное
     действие шага, пустоты под карточкой нет.
     */
    private var зона: some View {
        VStack(spacing: 0) {
            Image(systemName: "camera")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(КраскаПодачи.хорошоТекст)
                .frame(width: 64, height: 64)
                .background(КраскаПодачи.хорошоФон, in: Circle())
                .accessibilityHidden(true)
            Text(т("form_add_photo"))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(КраскаПодачи.текст)
                .padding(.top, 12)
            Text(т("add_photo_sub"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
                .padding(.bottom, 16)
            HStack(spacing: 10) {
                PhotosPicker(selection: $выбор, maxSelectionCount: max(1, модель.местоФото), selectionBehavior: .ordered,
                             matching: .images) {
                    кнопкаЗоны(т("form_gallery"), значок: "photo.on.rectangle", главная: true, широкая: true)
                }
                .buttonStyle(.plain)
                if КамераПодачи.есть {
                    Button { камера = true } label: {
                        кнопкаЗоны(т("form_camera"), значок: "camera", главная: false, широкая: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(String(format: т("form_photo_hint"), модель.лимитФото))
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
                .padding(.top, 12)
        }
        .padding(.vertical, 30)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 250)
        .background(КраскаПодачи.поле, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(КраскаПодачи.линия, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
        }
    }

    /// .photo-btn: высота 44, 14/700, скругление 12; главная — --g с белым, вторая — мятная --tint-ok с зелёным
    /// текстом и кромкой (вторичная кнопка кабинета).
    private func кнопкаЗоны(_ подпись: String, значок: String, главная: Bool, широкая: Bool = false) -> some View {
        HStack(spacing: 8) {
            Image(systemName: значок)
                .font(.system(size: 14, weight: .semibold))
                .accessibilityHidden(true)
            Text(подпись)
                .font(.system(size: 14, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(главная ? Color.white : КраскаПодачи.хорошоТекст)
        .padding(.horizontal, 16)
        .frame(maxWidth: широкая ? .infinity : nil)
        .frame(height: 44)
        .background(главная ? Theme.зелёный : КраскаПодачи.хорошоФон,
                    in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                .strokeBorder(главная ? Color.clear : КраскаПодачи.хорошоТекст.opacity(0.35), lineWidth: 1.5)
        }
        .contentShape(Rectangle())
    }

    /// Сетка: плитки переносятся пальцем (долгое нажатие), последняя клетка — «+ Добавить».
    private var сетка: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(Array(модель.плитки.enumerated()), id: \.element.id) { номер, плитка in
                ПлиткаФотоВид(плитка: плитка, главная: номер == 0,
                              главной: { модель.сделатьГлавным(плитка.id) },
                              удалить: { модель.удалитьФото(плитка.id) },
                              повторить: { модель.повторить(плитка.id) },
                              сдвинуть: { сдвиг in модель.сдвинутьФото(плитка.id, на: сдвиг) })
                    .opacity(тащим == плитка.id ? 0.45 : 1)
                    .onDrag {
                        тащим = плитка.id
                        return NSItemProvider(object: плитка.id.uuidString as NSString)
                    }
                    .onDrop(of: [UTType.text], delegate: ПереносФото(цель: плитка.id, тащим: $тащим,
                                                                     переставить: { a, b in модель.переставитьФото(a, к: b) }))
            }
            if модель.местоФото > 0 { маленькаяПлитка }
        }
        .onDrop(of: [UTType.text], delegate: КонецПереносаФото(тащим: $тащим))
    }

    private var маленькаяПлитка: some View {
        PhotosPicker(selection: $выбор, maxSelectionCount: max(1, модель.местоФото), selectionBehavior: .ordered,
                     matching: .images) {
            VStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                    .accessibilityHidden(true)
                Text(т("add_photo_short"))
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(КраскаПодачи.хорошоТекст)
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(КраскаПодачи.поле, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                    .strokeBorder(КраскаПодачи.линия, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel(т("add_photo_big"))
    }

    private var кнопкаКамеры: some View {
        Button {
            камера = true
        } label: {
            кнопкаЗоны(т("form_camera"), значок: "camera", главная: false, широкая: true)
        }
        .buttonStyle(.plain)
    }

    /// «Фото готовы — распознать?»: «Распознать» — POST recognize только по нажатию; «Заполнить вручную» — дальше.
    private var блокИИ: some View {
        КарточкаПодачи(т("rsh_done_t2"), подпись: т("rsh_done_ai_s")) {
            HStack(spacing: 10) {
                КнопкаПодачи(т("rsh_done_ai"), занято: модель.распознаём) { модель.распознать() }
                КнопкаПодачиВторая(т("form_manual")) { модель.далее() }
            }
            if let ии = модель.страница.состояние?.ии, ии.показать, !ии.оплачено || ии.лимит > 0 {
                ПодсказкаПоля(String(format: т("ai_left"), ии.осталось, ии.лимит))
            }
        }
    }
}

/// Плитка фото (.photo-thumb): картинка, «★ главное» у первой, «✕», кольцо загрузки, ошибка с «повторить».
struct ПлиткаФотоВид: View {
    let плитка: ПлиткаФото
    let главная: Bool
    let главной: () -> Void
    let удалить: () -> Void
    let повторить: () -> Void
    let сдвинуть: (Int) -> Void

    init(плитка: ПлиткаФото, главная: Bool, главной: @escaping () -> Void, удалить: @escaping () -> Void,
         повторить: @escaping () -> Void, сдвинуть: @escaping (Int) -> Void) {
        self.плитка = плитка
        self.главная = главная
        self.главной = главной
        self.удалить = удалить
        self.повторить = повторить
        self.сдвинуть = сдвинуть
    }

    private func т(_ ключ: String) -> String { ПодачаText.т(ключ) }

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
        return картинка
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .overlay(alignment: .bottom) {
                /* .main-photo::after — полоса «★ главное» по низу плитки. */
                if главная && плитка.готова {
                    Text("★ " + т("main_photo"))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(Color(uiColor: Theme.hex(0x34C997, 0.78)))
                        .accessibilityHidden(true)
                }
            }
            .clipShape(форма)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(главная ? т("cover") : т("photo"))
            .accessibilityAddTraits(.isImage)
            .accessibilityAction(named: Text(т("photo_left"))) { сдвинуть(-1) }
            .accessibilityAction(named: Text(т("photo_right"))) { сдвинуть(1) }
            .overlay {
                форма
                    .strokeBorder(главная ? Theme.зелёный2 : КраскаПодачи.линия, lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
            .background {
                if главная {
                    RoundedRectangle(cornerRadius: Theme.Радиус.md + 2, style: .continuous)
                        .fill(Color(uiColor: Theme.hex(0x0F5132, 0.25)))
                        .padding(-2)
                }
            }
            .shadow(color: Color(uiColor: Theme.hex(0x0F5132, 0.07)), radius: 2, y: 1)
            .overlay { состояние }
            .overlay(alignment: .topTrailing) {
                Button(action: удалить) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Color.white)
                        .frame(width: 26, height: 26)
                        .background(Color.black.opacity(0.6), in: Circle())
                        .padding(5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(т("delete"))
            }
            .contentShape(форма)
            .contextMenu {
                if !главная && плитка.готова {
                    Button(т("make_cover"), systemImage: "star") { главной() }
                }
                if плитка.ошибка != nil && плитка.картинка != nil {
                    Button(т("retry_photo"), systemImage: "arrow.clockwise") { повторить() }
                }
                Button(т("delete"), systemImage: "trash", role: .destructive) { удалить() }
            }
    }

    @ViewBuilder
    private var картинка: some View {
        if let превью = плитка.превью {
            Color.clear
                .overlay {
                    Image(uiImage: превью)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
        } else if let адрес = Config.url(плитка.url) {
            /* Адрес фото сервера (upload_photo → url, черновик, my_items) — только картинка, нажатием не открывается. */
            Color.clear
                .overlay {
                    AsyncImage(url: адрес) { фаза in
                        if let изображение = фаза.image {
                            изображение.resizable().scaledToFill()
                        } else {
                            Theme.поверхность2
                        }
                    }
                }
                .clipped()
        } else {
            Theme.поверхность2
        }
    }

    @ViewBuilder
    private var состояние: some View {
        if плитка.грузится {
            ZStack {
                Color.black.opacity(0.4)
                КольцоЗагрузки(этап: плитка.этап)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        } else if let ошибка = плитка.ошибка {
            VStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.white)
                    .accessibilityHidden(true)
                Text(ошибка)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                if плитка.картинка != nil {
                    Button(т("retry_photo")) { повторить() }
                        .font(.system(size: 11, weight: .bold))
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.зелёный)
                        .controlSize(.mini)
                }
            }
            .padding(4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.red.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        }
    }
}

// MARK: - Данные товара

struct ШагДанные: View {
    @ObservedObject var модель: ПодачаМодель
    let фокус: FocusState<String?>.Binding
    @State private var разделы = false

    init(модель: ПодачаМодель, фокус: FocusState<String?>.Binding) {
        self.модель = модель
        self.фокус = фокус
    }

    private func т(_ ключ: String) -> String { ПодачаText.т(ключ) }

    var body: some View {
        /* #add-card-data — одна карточка: название, раздел, описание (бренд — первым в характеристиках). */
        КарточкаПодачи(т(модель.режим == .услуга ? "card_what_service" : "step_what"), значок: "shippingbox") {
            название
            раздел
            описание
        }
        .sheet(isPresented: $разделы) {
            ЛистРазделов(справочники: модель.справочники, выбрано: модель.форма.раздел, выбрать: { ключ in
                модель.выбратьРаздел(ключ)
            })
        }
    }

    private var название: some View {
        let авто = модель.режим == .авто
        let ошибка = модель.ошибка("title")
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ПодписьПоля(т(модель.режим == .услуга ? "e_model_service" : "form_name"))
                if модель.заполненоИИ {
                    /* #ai-name-badge: 11/600, --tint-ok / --on-ok, скругление 6. */
                    Text(т("form_ai_badge"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(КраскаПодачи.хорошоТекст)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(КраскаПодачи.хорошоФон, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            ПолеПодачи(авто ? т("auto_title_ph") : т("form_name_ph"), текст: $модель.форма.название,
                       заблокировано: авто, фокус: фокус, ключ: авто ? nil : "title", ошибка: ошибка != nil,
                       предел: ПределыПодачи.название, счётчик: true)
            СтрокаОшибки(ошибка)
            if авто { ПодсказкаПоля(т("auto_title_hint")) }
        }
    }

    /// Раздел — select.inp на --card; нажатие — лист с поиском и крупными строками, путь — под строкой.
    private var раздел: some View {
        let ошибка = модель.ошибка("category")
        return VStack(alignment: .leading, spacing: 8) {
            ПодписьПоля(т("form_category"))
            СтрокаРазделаПодачи(справочники: модель.справочники, раздел: модель.форма.раздел, ошибка: ошибка != nil) {
                фокус.wrappedValue = nil
                разделы = true
            }
            СтрокаОшибки(ошибка)
        }
        .id("category")
    }

    /// Описание (label.field-sub): «* обязательно» — только здесь, как на сайте.
    private var описание: some View {
        let ошибка = модель.ошибка("desc")
        let длина = модель.форма.описание.count
        return VStack(alignment: .leading, spacing: 6) {
            ПодписьПоля(т("form_description"), обязательно: true, мелкая: true)
            ТекстПодачи(т(модель.режим == .услуга ? "desc_ph_service" : "form_desc_ph"), текст: $модель.форма.описание,
                        фокус: фокус, ключ: "desc", ошибка: ошибка != nil)
            HStack(alignment: .top, spacing: 8) {
                if ошибка != nil {
                    СтрокаОшибки(ошибка)
                } else {
                    ПодсказкаПоля(т("desc_min"))
                }
                Spacer(minLength: 0)
                Text(String(длина) + " / 5000")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(Theme.текстВторой)
                    .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - Характеристики

struct ШагХарактеристики: View {
    @ObservedObject var модель: ПодачаМодель
    let фокус: FocusState<String?>.Binding
    @State private var список: СписокВыбора? = nil

    init(модель: ПодачаМодель, фокус: FocusState<String?>.Binding) {
        self.модель = модель
        self.фокус = фокус
    }

    private func т(_ ключ: String) -> String { ПодачаText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch модель.режим {
            case .недвижимость:
                ПоляНедвижимости(модель: модель, фокус: фокус, показатьСписок: { с in список = с })
            case .авто:
                ПоляАвто(модель: модель, фокус: фокус, показатьСписок: { с in список = с })
            case .запчасти:
                ПоляЗапчасти(модель: модель, фокус: фокус, показатьСписок: { с in список = с })
            case .товар, .услуга, .работа:
                if !модель.характеристики.isEmpty || модель.брендВиден { характеристики }
            }
            if модель.vinРазрешён { vin }
        }
        .sheet(item: $список) { с in
            ЛистВыбора(список: с)
        }
    }

    /// Панель #specs-toggle + #specs-panel: шапка с ключом на --surf2, под ней бренд и поля E_SPECS по два в ряд
    /// (div.two); списки — select (меню или лист с «— не указано —» и «Другое (вписать)…»), число — полем;
    /// пишется в cpu/gpu/ram/storage/year.
    private var характеристики: some View {
        let ряды = модель.рядыХарактеристик
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "wrench.adjustable")
                    .font(.system(size: 13))
                    .accessibilityHidden(true)
                Text(т("form_specs"))
                    .font(.system(size: 14, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
            }
            .foregroundStyle(КраскаПодачи.текст)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(КраскаПодачи.поле,
                        in: UnevenRoundedRectangle(topLeadingRadius: Theme.Радиус.ms, topTrailingRadius: Theme.Радиус.ms,
                                                   style: .continuous))
            .overlay(alignment: .bottom) {
                Rectangle().fill(КраскаПодачи.линия).frame(height: 1)
            }
            VStack(alignment: .leading, spacing: 14) {
                if модель.брендВиден { бренд }
                if !ряды.isEmpty {
                    Grid(alignment: .topLeading, horizontalSpacing: 10, verticalSpacing: 14) {
                        ForEach(0..<ряды.count, id: \.self) { р in
                            ряд(ряды[р])
                        }
                    }
                }
            }
            .padding(14)
        }
        .overlay { форма.strokeBorder(КраскаПодачи.линия, lineWidth: 1) }
    }

    /// Ряд сетки: широкое поле (сегмент) — на обе колонки, иначе два поля по половине.
    @ViewBuilder
    private func ряд(_ поля: [ПолеХарактеристики]) -> some View {
        if поля.count == 1 && ШагХарактеристики.широкое(поля[0]) {
            GridRow(alignment: .bottom) {
                ячейка(поля[0])
                    .gridCellColumns(2)
            }
        } else if let первое = поля.first {
            GridRow(alignment: .bottom) {
                ячейка(первое)
                if поля.count > 1 {
                    ячейка(поля[1])
                } else {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                }
            }
        }
    }

    /// Сегментом — список из 2–4 коротких значений (правило подачи: сегмент · меню · лист с поиском).
    static func широкое(_ поле: ПолеХарактеристики) -> Bool {
        guard !поле.вводом, !поле.год else { return false }
        return ВыборСегментом.влезет(поле.вариантыСПодписью)
    }

    private func ячейка(_ поле: ПолеХарактеристики) -> some View {
        let ключ = "sp_" + поле.поле
        let ошибка = модель.ошибка(ключ)
        return VStack(alignment: .leading, spacing: 6) {
            ПодписьПоля(поле.подпись, обязательно: поле.обязательно, мелкая: true)
                .fixedSize(horizontal: false, vertical: true)
            полеХарактеристики(поле)
            СтрокаОшибки(ошибка)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(поле.вводом ? "cell_" + ключ : ключ)
    }

    /// Бренд (label.field-sub): список BRAND_LIST раздела на --surf2 с «Другой — вписать» или просто поле.
    private var бренд: some View {
        let бренды = модель.бренды
        return VStack(alignment: .leading, spacing: 6) {
            ПодписьПоля(т("form_brand"), обязательно: модель.брендОбязателен, необязательно: !модель.брендОбязателен,
                        мелкая: true)
            if бренды.isEmpty {
                ПолеПодачи(т("form_brand_ph"), текст: $модель.форма.бренд, заглавные: .words, фокус: фокус, ключ: "brand",
                           ошибка: модель.ошибка("brand") != nil, предел: ПределыПодачи.короткое)
            } else {
                СтрокаВыбора(модель.форма.бренд, подсказка: т("form_brand_pick"), заливка: КраскаПодачи.поле) {
                    let м = модель
                    фокус.wrappedValue = nil
                    список = СписокВыбора(заголовок: т("form_brand"),
                                          варианты: бренды.map { ВариантПоля(ключ: $0, подпись: $0) },
                                          своё: т("form_brand_other"), сброс: т("spec_unset")) { значение in
                        м.форма.бренд = значение
                    }
                }
                .id("brand")
            }
            СтрокаОшибки(модель.ошибка("brand"))
        }
    }

    /// Поле по виду: год — списком лет; ввод — полем (число — цифровой клавиатурой); список — сегментом (2–4 коротких),
    /// меню (до 15) или листом с поиском. Подписи значений — на языке телефона, на сервер уходит значение сайта.
    @ViewBuilder
    private func полеХарактеристики(_ поле: ПолеХарактеристики) -> some View {
        let связь = значение(поле.поле)
        let варианты = вариантыПоля(поле, связь.wrappedValue)
        let ошибка = модель.ошибка("sp_" + поле.поле) != nil
        if поле.год {
            ВыборГодаПодачи(значение: связь)
        } else if поле.вводом {
            ПолеПодачи(поле.подсказка.isEmpty ? поле.подпись : поле.подсказка, текст: связь,
                       клавиатура: поле.числом ? (поле.дробное ? .decimalPad : .numberPad) : .default,
                       фокус: фокус, ключ: "sp_" + поле.поле, ошибка: ошибка, предел: ПределыПодачи.короткое)
        } else if ШагХарактеристики.широкое(поле) && варианты.count == поле.вариантыСПодписью.count {
            ВыборСегментом(варианты, значение: связь, можноСнять: true)
        } else if варианты.count <= 15 {
            МенюВыбора(варианты, значение: связь, подсказка: т("spec_unset"), сброс: т("spec_unset"),
                       своё: своёДействие(поле, связь))
        } else {
            СтрокаВыбора(связь.wrappedValue.isEmpty ? "" : показ(варианты, связь.wrappedValue),
                         подсказка: т("spec_unset")) {
                фокус.wrappedValue = nil
                список = СписокВыбора(заголовок: поле.подпись, варианты: варианты,
                                      своё: поле.своё ? т("spec_other_write") : nil, сброс: т("spec_unset")) { новое in
                    связь.wrappedValue = новое
                }
            }
        }
    }

    /// «Другое (вписать)…» в меню — если у поля оно есть (у всех списков сайта есть).
    private func своёДействие(_ поле: ПолеХарактеристики, _ связь: Binding<String>) -> (() -> Void)? {
        guard поле.своё else { return nil }
        return { вписать(поле, связь) }
    }

    /// Подпись выбранного значения (значение не из списка — как есть).
    private func показ(_ варианты: [ВариантПоля], _ значение: String) -> String {
        варианты.first(where: { $0.ключ == значение })?.подпись ?? значение
    }

    /// Варианты раздела; значение не из списка (вписали или Kliko AI) — отдельным вариантом, чтобы его было видно.
    private func вариантыПоля(_ поле: ПолеХарактеристики, _ сейчас: String) -> [ВариантПоля] {
        var итог = поле.вариантыСПодписью
        if !сейчас.isEmpty && !итог.contains(where: { $0.ключ == сейчас }) {
            итог.append(ВариантПоля(ключ: сейчас, подпись: сейчас))
        }
        return итог
    }

    private func вписать(_ поле: ПолеХарактеристики, _ связь: Binding<String>) {
        фокус.wrappedValue = nil
        список = СписокВыбора(заголовок: поле.подпись, варианты: [], своё: т("spec_other_write"), пишу: true) { новое in
            связь.wrappedValue = новое
        }
    }

    /// Поле API по имени f из E_SPECS.
    private func значение(_ поле: String) -> Binding<String> {
        switch поле {
        case "cpu": return $модель.форма.cpu
        case "gpu": return $модель.форма.gpu
        case "ram": return $модель.форма.ram
        case "storage": return $модель.форма.storage
        default: return $модель.форма.year
        }
    }

    /// VIN — 17 знаков заглавными; в подаче «— необязательно, подставит марку и год».
    private var vin: some View {
        КарточкаПодачи {
            VStack(alignment: .leading, spacing: 6) {
                ПодписьПоля(т("vin_label"))
                ПолеПодачи(т("vin_ph"), текст: vinСвязь, заглавные: .characters, фокус: фокус, ключ: "vin")
            }
        }
    }

    private var vinСвязь: Binding<String> {
        let связь = $модель.форма.vin
        return Binding(get: { связь.wrappedValue }, set: { новое in
            let чистое = String(новое.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(17))
            if чистое != связь.wrappedValue { связь.wrappedValue = чистое }
        })
    }
}

extension ПодачаМодель {
    /// Характеристики рядами сетки: два поля в ряд, сегмент — на весь ряд (одиночное поле ждёт пару, чтобы не было дыр).
    var рядыХарактеристик: [[ПолеХарактеристики]] {
        var ряды: [[ПолеХарактеристики]] = []
        var ждёт: ПолеХарактеристики? = nil
        for поле in характеристики {
            if ШагХарактеристики.широкое(поле) {
                ряды.append([поле])
            } else if let первое = ждёт {
                ряды.append([первое, поле])
                ждёт = nil
            } else {
                ждёт = поле
            }
        }
        if let последнее = ждёт { ряды.append([последнее]) }
        return ряды
    }
}

/// Мастер недвижимости (_rw2): «Продаю / Сдаю», вид объекта, поля REALTY_FIELDS[сделка][вид].
struct ПоляНедвижимости: View {
    @ObservedObject var модель: ПодачаМодель
    let фокус: FocusState<String?>.Binding
    let показатьСписок: (СписокВыбора) -> Void

    init(модель: ПодачаМодель, фокус: FocusState<String?>.Binding, показатьСписок: @escaping (СписокВыбора) -> Void) {
        self.модель = модель
        self.фокус = фокус
        self.показатьСписок = показатьСписок
    }

    private func т(_ ключ: String) -> String { ПодачаText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            КарточкаПодачи(т("as_realty")) {
                VStack(alignment: .leading, spacing: 6) {
                    ПодписьПоля(т("as_rl_deal_q"))
                    ВыборСегментом([ВариантПоля(ключ: "sale", подпись: т("as_rl_sale")),
                                    ВариантПоля(ключ: "rent", подпись: т("as_rl_rent"))],
                                   значение: $модель.форма.сделка)
                }
                VStack(alignment: .leading, spacing: 6) {
                    ПодписьПоля(т("as_rl_kind_q"))
                    if ВыборСегментом.влезет(виды) {
                        ВыборСегментом(виды, значение: вид)
                    } else {
                        ПотокЧипов(зазор: 8) {
                            ForEach(виды, id: \.self) { в in
                                ЧипПодачи(в.подпись, выбран: модель.форма.вид == в.ключ) { сменитьВид(в.ключ) }
                            }
                        }
                    }
                }
            }
            if !модель.поляНедвижимости.isEmpty {
                КарточкаПодачи(т("rw_params"), подпись: модель.названиеНедвижимости()) {
                    ForEach(модель.поляНедвижимости) { поле in
                        ПолеМастераВид(поле: поле, значение: значение(поле.id), флаг: флаг(поле.id), варианты: поле.варианты,
                                       показатьСписок: показатьСписок, фокус: фокус, ключФокуса: "rf_" + поле.id)
                    }
                }
            }
        }
    }

    private var виды: [ВариантПоля] {
        [ВариантПоля(ключ: "apartment", подпись: т("rl_flat")), ВариантПоля(ключ: "house", подпись: т("rl_house")),
         ВариантПоля(ключ: "commercial", подпись: т("rl_office")), ВариантПоля(ключ: "land", подпись: т("rl_land"))]
    }

    private var вид: Binding<String> {
        let м = модель
        return Binding(get: { м.форма.вид }, set: { новое in
            guard !новое.isEmpty, м.форма.вид != новое else { return }
            var ф = м.форма
            ф.вид = новое
            ф.недвижимость = ["owner": "owner"]
            ф.флагиНедвижимости = [:]
            м.форма = ф
        })
    }

    /// _rw2Pick: новый вид — поля заново, «Кто размещает» по умолчанию «Собственник».
    private func сменитьВид(_ вид: String) {
        guard !вид.isEmpty, модель.форма.вид != вид else { return }
        var ф = модель.форма
        ф.вид = вид
        ф.недвижимость = ["owner": "owner"]
        ф.флагиНедвижимости = [:]
        модель.форма = ф
    }

    private func значение(_ ключ: String) -> Binding<String> {
        let м = модель
        return Binding(get: { м.форма.недвижимость[ключ] ?? "" }, set: { новое in
            if новое.isEmpty {
                м.форма.недвижимость.removeValue(forKey: ключ)
            } else {
                м.форма.недвижимость[ключ] = новое
            }
        })
    }

    private func флаг(_ ключ: String) -> Binding<Bool> {
        let м = модель
        return Binding(get: { м.форма.флагиНедвижимости[ключ] ?? false }, set: { новое in
            м.форма.флагиНедвижимости[ключ] = новое
        })
    }
}

/// Одно поле мастеров недвижимости и запчастей по его виду (chips · num · select · toggle · text · ptype):
/// 2–4 коротких варианта — сегмент, до 15 — меню (select) или чипы (chips), больше — лист с поиском.
struct ПолеМастераВид: View {
    let поле: ПолеМастера
    @Binding var значение: String
    @Binding var флаг: Bool
    let варианты: [ВариантПоля]
    let показатьСписок: (СписокВыбора) -> Void
    let фокус: FocusState<String?>.Binding?
    let ключФокуса: String

    init(поле: ПолеМастера, значение: Binding<String>, флаг: Binding<Bool>, варианты: [ВариантПоля],
         показатьСписок: @escaping (СписокВыбора) -> Void, фокус: FocusState<String?>.Binding? = nil,
         ключФокуса: String = "") {
        self.поле = поле
        self._значение = значение
        self._флаг = флаг
        self.варианты = варианты
        self.показатьСписок = показатьСписок
        self.фокус = фокус
        self.ключФокуса = ключФокуса
    }

    var body: some View {
        switch поле.вид {
        case "toggle":
            ПереключательПодачи(поле.подпись, включено: $флаг)
        case "chips":
            VStack(alignment: .leading, spacing: 6) {
                подпись
                if ВыборСегментом.влезет(варианты) {
                    ВыборСегментом(варианты, значение: $значение, можноСнять: !поле.обязательно)
                } else {
                    ПотокЧипов(зазор: 8) {
                        ForEach(варианты, id: \.self) { в in
                            ЧипПодачи(в.подпись, выбран: значение == в.ключ) {
                                значение = значение == в.ключ ? "" : в.ключ
                            }
                        }
                    }
                }
            }
        case "select", "ptype":
            VStack(alignment: .leading, spacing: 6) {
                подпись
                if варианты.count > 15 {
                    СтрокаВыбора(варианты.first(where: { $0.ключ == значение })?.подпись ?? значение,
                                 подсказка: ПодачаText.т("spec_unset")) {
                        открытьСписок()
                    }
                } else if ВыборСегментом.влезет(варианты) {
                    ВыборСегментом(варианты, значение: $значение, можноСнять: true)
                } else {
                    МенюВыбора(варианты, значение: $значение, подсказка: ПодачаText.т("spec_unset"),
                               сброс: ПодачаText.т("spec_unset"))
                }
            }
        case "num":
            VStack(alignment: .leading, spacing: 6) {
                подпись
                ПолеПодачи(поле.подпись, текст: числовое, клавиатура: .decimalPad, фокус: фокус,
                           ключ: ключФокуса.isEmpty ? nil : ключФокуса, единица: поле.единица)
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                подпись
                ПолеПодачи(поле.подпись, текст: $значение, фокус: фокус, ключ: ключФокуса.isEmpty ? nil : ключФокуса,
                           предел: ПределыПодачи.короткое)
            }
        }
    }

    private func открытьСписок() {
        let связь = $значение
        if let фокус { фокус.wrappedValue = nil }
        показатьСписок(СписокВыбора(заголовок: поле.подпись, варианты: варианты,
                                    сброс: ПодачаText.т("spec_unset")) { новое in
            связь.wrappedValue = новое
        })
    }

    /// Подпись .field-sub (13/600 серым) с «* обязательно»; единица у числа — справа в самом поле.
    private var подпись: some View {
        let единица = (поле.вид == "num" || поле.единица.isEmpty) ? "" : ", " + поле.единица
        return ПодписьПоля(поле.подпись + единица, обязательно: поле.обязательно, мелкая: true)
    }

    /// Числа — только цифры и точка/запятая: «85 000 км» отбор витрины прочитал бы как ноль.
    private var числовое: Binding<String> {
        let связь = $значение
        return Binding(get: { связь.wrappedValue }, set: { новое in
            связь.wrappedValue = ПодачаМодель.дробное(новое)
        })
    }
}

/// «Год выпуска»: меню лет от текущего (по календарю, не зашито) до 2000, новые сверху, и «— не указано —»;
/// вписать нельзя. Год правки вне списка (старше 2000) остаётся и виден выбранным.
struct ВыборГодаПодачи: View {
    @Binding var значение: String

    init(значение: Binding<String>) {
        self._значение = значение
    }

    var body: some View {
        МенюВыбора(варианты, значение: $значение, подсказка: ПодачаText.т("spec_unset"),
                   сброс: ПодачаText.т("spec_unset"))
    }

    private var варианты: [ВариантПоля] {
        var годы = ПределыПодачи.годы
        if !значение.isEmpty && !годы.contains(значение) { годы.append(значение) }
        return годы.map { ВариантПоля(ключ: $0, подпись: $0) }
    }
}

/// Мастер авто (_aw2): марка → модель → поколение → год, пробег, объём → коробка и топливо.
struct ПоляАвто: View {
    @ObservedObject var модель: ПодачаМодель
    let фокус: FocusState<String?>.Binding
    let показатьСписок: (СписокВыбора) -> Void

    init(модель: ПодачаМодель, фокус: FocusState<String?>.Binding, показатьСписок: @escaping (СписокВыбора) -> Void) {
        self.модель = модель
        self.фокус = фокус
        self.показатьСписок = показатьСписок
    }

    private func т(_ ключ: String) -> String { ПодачаText.т(ключ) }

    /// AW_GEAR и AW_FUEL сайта — «слова те же, что в фильтре витрины»: уходят по-русски на любом языке.
    private static let коробки = ["Автомат", "Механика", "Робот", "Вариатор"]
    private static let топливо = ["Бензин", "Дизель", "Газ", "Гибрид", "Электро"]

    var body: some View {
        let тм = МастерПодачиText.т
        let есть = !модель.форма.бренд.trimmingCharacters(in: .whitespaces).isEmpty
        return VStack(alignment: .leading, spacing: 14) {
            /* Марка, модель и поколение — только мастером (справочник сайта): название собирается из них. */
            VStack(alignment: .leading, spacing: 6) {
                ВходМастераПодачи(значок: "car", заголовок: тм(есть ? "aw_entry_t" : "aw_entry_new"),
                                  подпись: есть ? модель.сводкаАвто : тм("aw_entry_s"), заполнено: есть,
                                  ошибка: модель.ошибка("auto") != nil) {
                    фокус.wrappedValue = nil
                    модель.открытьМастерАвто()
                }
                СтрокаОшибки(модель.ошибка("auto"))
            }
            .id("auto")
            КарточкаПодачи(т("aw_params")) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        ПодписьПоля(т("aw_year"))
                        ВыборГодаПодачи(значение: $модель.форма.year)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        ПодписьПоля(т("aw_mileage"))
                        ПолеПодачи("85000", текст: цифры($модель.форма.ram, предел: 7), клавиатура: .numberPad,
                                   фокус: фокус, ключ: "mileage")
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    ПодписьПоля(т("aw_engine"))
                    ПолеПодачи("1.6", текст: объём, клавиатура: .decimalPad, фокус: фокус, ключ: "engine")
                    ПодсказкаПоля(т("aw_nums_hint"))
                }
                VStack(alignment: .leading, spacing: 6) {
                    ПодписьПоля(т("aw_gear"))
                    ВыборСегментом(Self.коробки.map { ВариантПоля(ключ: $0, подпись: $0) }, значение: $модель.форма.cpu,
                                   можноСнять: true)
                }
                VStack(alignment: .leading, spacing: 6) {
                    ПодписьПоля(т("aw_fuel"))
                    ПотокЧипов(зазор: 8) {
                        ForEach(Self.топливо, id: \.self) { к in
                            ЧипПодачи(к, выбран: модель.форма.gpu == к) {
                                модель.форма.gpu = модель.форма.gpu == к ? "" : к
                            }
                        }
                    }
                }
            }
        }
    }

    private func цифры(_ связь: Binding<String>, предел: Int) -> Binding<String> {
        Binding(get: { связь.wrappedValue }, set: { новое in
            связь.wrappedValue = ПодачаМодель.цифры(новое, предел: предел)
        })
    }

    private var объём: Binding<String> {
        let связь = $модель.форма.storage
        return Binding(get: { связь.wrappedValue }, set: { новое in
            связь.wrappedValue = ПодачаМодель.дробное(новое, предел: 4)
        })
    }
}

/// Мастер запчастей (_pw2): вид по разделу (_pwKindFor), поля PARTS_FIELDS[вид]; «Что за деталь» — /api/parts_types.php.
struct ПоляЗапчасти: View {
    @ObservedObject var модель: ПодачаМодель
    let фокус: FocusState<String?>.Binding
    let показатьСписок: (СписокВыбора) -> Void

    init(модель: ПодачаМодель, фокус: FocusState<String?>.Binding, показатьСписок: @escaping (СписокВыбора) -> Void) {
        self.модель = модель
        self.фокус = фокус
        self.показатьСписок = показатьСписок
    }

    var body: some View {
        КарточкаПодачи(ПодачаText.т("pw_title"), подпись: ПодачаText.т("pw_sub")) {
            ForEach(модель.поляЗапчасти) { поле in
                ПолеМастераВид(поле: поле, значение: значение(поле.id), флаг: флаг(поле.id),
                               варианты: поле.вид == "ptype" ? модель.типыЗапчастей : поле.варианты,
                               показатьСписок: показатьСписок, фокус: фокус, ключФокуса: "pf_" + поле.id)
            }
        }
        .task { await модель.загрузитьТипыЗапчастей() }
    }

    private func значение(_ ключ: String) -> Binding<String> {
        let м = модель
        return Binding(get: { м.форма.запчасть[ключ] ?? "" }, set: { новое in
            м.форма.запчасть[ключ] = новое
        })
    }

    /// Переключателей у PARTS_FIELDS нет; на случай нового — «1» / пусто.
    private func флаг(_ ключ: String) -> Binding<Bool> {
        let м = модель
        return Binding(get: { (м.форма.запчасть[ключ] ?? "") == "1" }, set: { новое in
            м.форма.запчасть[ключ] = новое ? "1" : ""
        })
    }
}
