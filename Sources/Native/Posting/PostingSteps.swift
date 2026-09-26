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
    let открытьСайт: (String) -> Void
    @FocusState private var фокус: String?

    init(модель: ПодачаМодель, открытьСайт: @escaping (String) -> Void) {
        self.модель = модель
        self.открытьСайт = открытьСайт
    }

    private func т(_ ключ: String) -> String { ПодачаText.т(ключ) }

    var body: some View {
        ScrollViewReader { прокрутка in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Color.clear
                        .frame(height: 0)
                        .id("верх")
                    if модель.страница.нуженEgov && !модель.правка && (модель.шаг == .фото || модель.шаг == .проверка) {
                        плашкаEgov
                    }
                    if !модель.правка && модель.шаг == .фото { полосаТипа }
                    шаг
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .scrollDismissesKeyboard(.interactively)
            .submitLabel(.next)
            .onSubmit { перейтиКПолю(1) }
            .onChange(of: фокус) { _, ключ in
                guard let ключ else { return }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    withAnimation(.easeOut(duration: 0.25)) { прокрутка.scrollTo(ключ, anchor: .center) }
                }
            }
            .onChange(of: модель.шаг) { _, _ in
                фокус = nil
                withAnimation(.easeOut(duration: 0.2)) { прокрутка.scrollTo("верх", anchor: .top) }
            }
            .onChange(of: модель.ошибкиПолей) { было, стало in
                /* Новая ошибка — показать её поле (после перехода на нужный шаг). */
                guard let ключ = стало.keys.first(where: { было[$0] == nil }) else { return }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    withAnimation(.easeOut(duration: 0.25)) { прокрутка.scrollTo(ключ, anchor: .center) }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { полоса }
        .safeAreaInset(edge: .bottom, spacing: 0) { низ }
    }

    // MARK: Шапка шага

    /// «Шаг 2 из 5 · Данные товара» и тонкая полоса хода; в правке — ряд шагов с точкой у изменённых.
    private var полоса: some View {
        let н = модель.номерШага
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: т("step_of"), н.номер, н.всего))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                Text("·")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                Text(модель.шаг.название)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            ProgressView(value: Double(н.номер), total: Double(н.всего))
                .tint(Theme.зелёныйЯркий)
                .animation(.easeInOut(duration: 0.25), value: н.номер)
                .accessibilityHidden(true)
            if модель.правка { полосаПравки }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.поверхность)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.линия).frame(height: 1)
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
                Text(ш.название)
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)
                if изменён {
                    Circle()
                        .fill(Theme.золото)
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(текущий ? Theme.акцент : Theme.текстВторой)
            .padding(.horizontal, 10)
            .frame(minHeight: 30)
            .background(текущий ? Theme.оттенокАкцента : Theme.поверхность2, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(текущий ? .isSelected : [])
        .accessibilityValue(изменён ? т("edited") : "")
    }

    /// #add-ver-bar: без верификации объявление ждёт в кабинете.
    private var плашкаEgov: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(т("ver_bar_t"))
                .font(.system(size: 14, weight: .bold))
            Text(т("ver_bar_s"))
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
            Button(т("ver_bar_go")) { ВерификацияПоверх.показать() }
                .font(.system(size: 14, weight: .bold))
                .buttonStyle(.borderedProminent)
                .tint(Theme.зелёный)
        }
        .foregroundStyle(КраскаОбъявлений.предупреждениеТекст)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(КраскаОбъявлений.предупреждениеФон, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
    }

    /// Полоса выбранного типа с «Изменить» (_AFT_META сайта).
    private var полосаТипа: some View {
        HStack(spacing: 10) {
            ЗначокРазделаПодачи(корень: модель.корень)
            VStack(alignment: .leading, spacing: 1) {
                Text(названиеТипа)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.текст)
                    .lineLimit(1)
                if let топ = модель.форма.топ {
                    Text(String(format: т("top_bar"), топ.подпись))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.золото)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Button(т("change")) { модель.сменитьТип() }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.акцент)
        }
        .padding(10)
        .background(Theme.оттенокАкцента, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
    }

    private var названиеТипа: String {
        let раздел = модель.справочники.имя(модель.форма.раздел)
        if !модель.форма.плитка.isEmpty { return модель.форма.плитка }
        return раздел.isEmpty ? т("as_goods") : раздел
    }

    @ViewBuilder
    private var шаг: some View {
        switch модель.шаг {
        case .фото: ШагФото(модель: модель)
        case .данные: ШагДанные(модель: модель, фокус: $фокус)
        case .характеристики: ШагХарактеристики(модель: модель, фокус: $фокус)
        case .цена: ШагЦена(модель: модель, фокус: $фокус)
        case .адрес: ШагАдрес(модель: модель, фокус: $фокус)
        case .дополнительно: ШагДополнительно(модель: модель, фокус: $фокус, открытьСайт: открытьСайт)
        case .проверка: ШагПроверка(модель: модель, открытьСайт: открытьСайт)
        }
    }

    // MARK: Низ

    /// Низ всегда на экране (над полосой «домой»): «‹ Назад» и главная кнопка; с клавиатурой — «↑ ↓ Готово».
    private var низ: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.линия).frame(height: 1)
            Group {
                if фокус != nil {
                    панельКлавиатуры
                } else {
                    кнопкиШагов
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, фокус != nil ? 6 : 10)
        }
        .background(Theme.поверхность.ignoresSafeArea(edges: .bottom))
    }

    @ViewBuilder
    private var кнопкиШагов: some View {
        let первый = модель.видимыеШаги.first == модель.шаг
        let последний = модель.шаг == .проверка
        HStack(spacing: 10) {
            if !первый {
                КнопкаНазадПодачи {
                    модель.назад()
                }
            }
            if модель.правка {
                if !последний {
                    КнопкаПодачиВторая(т("next")) { модель.далее() }
                }
                КнопкаПодачи(т(модель.отправляем ? "saving" : "save"), занято: модель.отправляем) { модель.сохранить() }
            } else if последний {
                КнопкаПодачи(кнопкаОтправки, занято: модель.отправляем) { модель.выставить() }
            } else {
                КнопкаПодачи(т("next")) { модель.далее() }
            }
        }
    }

    private var кнопкаОтправки: String {
        if модель.отправляем { return т("sending") }
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
        switch модель.шаг {
        case .данные:
            if модель.режим != .авто { п.append("title") }
            if модель.брендВиден && модель.бренды.isEmpty { п.append("brand") }
            п.append("desc")
        case .характеристики:
            switch модель.режим {
            case .авто:
                п.append(contentsOf: ["mileage", "engine"])
            case .недвижимость:
                for поле in модель.поляНедвижимости where поле.вид == "num" || поле.вид == "text" { п.append("rf_" + поле.id) }
            case .запчасти:
                for поле in модель.поляЗапчасти where поле.вид == "num" || поле.вид == "text" { п.append("pf_" + поле.id) }
            case .товар, .услуга, .работа:
                for поле in модель.характеристики where поле.варианты.isEmpty && поле.поле != "year" {
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
        case .дополнительно:
            if !модель.правка && модель.строкиДополнительно.contains("del") { п.append("deldays") }
        case .фото, .проверка:
            break
        }
        return п
    }
}

// MARK: - Фото

struct ШагФото: View {
    @ObservedObject var модель: ПодачаМодель
    @State private var выбор: [PhotosPickerItem] = []
    @State private var камера = false
    @State private var тащим: UUID? = nil

    init(модель: ПодачаМодель) {
        self.модель = модель
    }

    private func т(_ ключ: String) -> String { ПодачаText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            КарточкаПодачи(т("form_add_photo"), подпись: подпись) {
                if модель.плитки.isEmpty {
                    большаяПлитка
                } else {
                    сетка
                }
                if КамераПодачи.есть && модель.местоФото > 0 { кнопкаКамеры }
                if модель.местоФото == 0 {
                    ПодсказкаПоля(String(format: т("photo_cap_full"), модель.лимитФото))
                }
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

    /// «2 из 5 фото · первое — обложка, перетащите, чтобы поменять порядок».
    private var подпись: String {
        if модель.плитки.isEmpty { return String(format: т("form_photo_hint"), модель.лимитФото) }
        let счёт = String(format: т("photo_count"), модель.плитки.count, модель.лимитФото)
        return счёт + " · " + т("photo_order_hint")
    }

    /// Пусто — одна большая плитка «Добавить фото» (галерея).
    private var большаяПлитка: some View {
        PhotosPicker(selection: $выбор, maxSelectionCount: max(1, модель.местоФото), selectionBehavior: .ordered,
                     matching: .images) {
            VStack(spacing: 8) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(Theme.акцент)
                    .accessibilityHidden(true)
                Text(т("add_photo_big"))
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                Text(т("add_photo_sub"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 190)
            .background(Theme.мята, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                    .strokeBorder(Theme.акцент.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel(т("add_photo_big"))
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
                    .font(.system(size: 22, weight: .bold))
                    .accessibilityHidden(true)
                Text(т("add_photo_short"))
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(Theme.акцент)
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(Theme.мята, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                    .strokeBorder(Theme.акцент.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel(т("add_photo_big"))
    }

    private var кнопкаКамеры: some View {
        Button {
            камера = true
        } label: {
            Label(т("form_camera"), systemImage: "camera")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.акцент)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Theme.оттенокАкцента, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
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

/// Плитка фото (.photo-thumb): картинка, «Обложка» у первой, «✕», кольцо загрузки, ошибка с «повторить».
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
        картинка
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(главная ? т("cover") : т("photo"))
            .accessibilityAddTraits(.isImage)
            .accessibilityAction(named: Text(т("photo_left"))) { сдвинуть(-1) }
            .accessibilityAction(named: Text(т("photo_right"))) { сдвинуть(1) }
            .overlay {
                if главная {
                    RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                        .strokeBorder(Theme.зелёныйЯркий, lineWidth: 2.5)
                        .allowsHitTesting(false)
                }
            }
            .overlay { состояние }
            .overlay(alignment: .bottomLeading) {
                if главная && плитка.готова {
                    Text(т("cover"))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Theme.зелёный, in: Capsule())
                        .padding(6)
                        .accessibilityHidden(true)
                }
            }
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
            .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
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
            .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
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
            .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        }
    }
}

// MARK: - Данные товара

struct ШагДанные: View {
    @ObservedObject var модель: ПодачаМодель
    let фокус: FocusState<String?>.Binding
    @State private var список: СписокВыбора? = nil
    @State private var разделы = false

    init(модель: ПодачаМодель, фокус: FocusState<String?>.Binding) {
        self.модель = модель
        self.фокус = фокус
    }

    private func т(_ ключ: String) -> String { ПодачаText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            КарточкаПодачи(т(модель.режим == .услуга ? "card_what_service" : "card_what")) {
                название
                раздел
                if модель.брендВиден { бренд }
            }
            КарточкаПодачи {
                описание
            }
        }
        .sheet(item: $список) { с in
            ЛистВыбора(список: с)
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
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ПодписьПоля(т(модель.режим == .услуга ? "e_model_service" : "form_name"), обязательно: !авто)
                if модель.заполненоИИ {
                    Text(т("form_ai_badge"))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.акцент)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.оттенокАкцента, in: Capsule())
                }
            }
            ПолеПодачи(авто ? т("auto_title_ph") : т("form_name_ph"), текст: $модель.форма.название,
                       заблокировано: авто, фокус: фокус, ключ: авто ? nil : "title", ошибка: ошибка != nil,
                       предел: ПределыПодачи.название, счётчик: true)
            СтрокаОшибки(ошибка)
            if авто { ПодсказкаПоля(т("auto_title_hint")) }
        }
    }

    /// Раздел — одна строка со значком и путём; нажатие — лист с поиском и крупными строками.
    private var раздел: some View {
        let ошибка = модель.ошибка("category")
        return VStack(alignment: .leading, spacing: 6) {
            ПодписьПоля(т("form_category"), обязательно: true)
            СтрокаРазделаПодачи(справочники: модель.справочники, раздел: модель.форма.раздел, ошибка: ошибка != nil) {
                фокус.wrappedValue = nil
                разделы = true
            }
            СтрокаОшибки(ошибка)
        }
        .id("category")
    }

    /// Бренд: список BRAND_LIST раздела с «Другой — вписать» или просто поле.
    private var бренд: some View {
        let бренды = модель.бренды
        return VStack(alignment: .leading, spacing: 6) {
            ПодписьПоля(т("form_brand"), необязательно: true)
            if бренды.isEmpty {
                ПолеПодачи(т("form_brand_ph"), текст: $модель.форма.бренд, заглавные: .words, фокус: фокус, ключ: "brand",
                           предел: ПределыПодачи.короткое)
            } else {
                СтрокаВыбора(модель.форма.бренд, подсказка: т("form_brand_pick")) {
                    let м = модель
                    фокус.wrappedValue = nil
                    список = СписокВыбора(заголовок: т("form_brand"),
                                          варианты: бренды.map { ВариантПоля(ключ: $0, подпись: $0) },
                                          своё: т("form_brand_other"), сброс: т("spec_unset")) { значение in
                        м.форма.бренд = значение
                    }
                }
            }
        }
    }

    private var описание: some View {
        let ошибка = модель.ошибка("desc")
        let длина = модель.форма.описание.count
        return VStack(alignment: .leading, spacing: 6) {
            ПодписьПоля(т("form_description"), обязательно: true)
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
                if !модель.характеристики.isEmpty { характеристики }
            }
            if модель.vinРазрешён { vin }
        }
        .sheet(item: $список) { с in
            ЛистВыбора(список: с)
        }
    }

    /// E_SPECS: сегмент, меню или лист с «— не указано —» и «Другое (вписать)…», число — числовым полем;
    /// пишется в cpu/gpu/ram/storage/year.
    private var характеристики: some View {
        КарточкаПодачи(т("form_specs"), подпись: т("specs_sub")) {
            ForEach(модель.характеристики) { поле in
                VStack(alignment: .leading, spacing: 6) {
                    ПодписьПоля(поле.подпись)
                    полеХарактеристики(поле)
                }
            }
        }
    }

    @ViewBuilder
    private func полеХарактеристики(_ поле: ПолеХарактеристики) -> some View {
        let связь = значение(поле.поле)
        let варианты = вариантыПоля(поле, связь.wrappedValue)
        if поле.поле == "year" {
            ВыборГодаПодачи(значение: связь)
        } else if поле.варианты.isEmpty {
            ПолеПодачи(поле.подпись, текст: связь, клавиатура: .numberPad, фокус: фокус, ключ: "sp_" + поле.поле,
                       предел: ПределыПодачи.короткое)
        } else if ВыборСегментом.влезет(варианты) {
            ВыборСегментом(варианты, значение: связь, можноСнять: true)
            Button(т("spec_other_write")) { вписать(поле, связь) }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.акцент)
                .buttonStyle(.plain)
        } else if варианты.count <= 15 {
            МенюВыбора(варианты, значение: связь, подсказка: т("spec_unset"), сброс: т("spec_unset"),
                       своё: { вписать(поле, связь) })
        } else {
            СтрокаВыбора(связь.wrappedValue, подсказка: т("spec_unset")) {
                фокус.wrappedValue = nil
                список = СписокВыбора(заголовок: поле.подпись, варианты: варианты,
                                      своё: т("spec_other_write"), сброс: т("spec_unset")) { новое in
                    связь.wrappedValue = новое
                }
            }
        }
    }

    /// Варианты раздела; значение не из списка (вписали или Kliko AI) — отдельным вариантом, чтобы его было видно.
    private func вариантыПоля(_ поле: ПолеХарактеристики, _ сейчас: String) -> [ВариантПоля] {
        var итог = поле.варианты.map { ВариантПоля(ключ: $0, подпись: $0) }
        if !сейчас.isEmpty && !поле.варианты.contains(сейчас) {
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

    /// Подпись с «* обязательно»; единица у числа — справа в самом поле.
    private var подпись: some View {
        let единица = (поле.вид == "num" || поле.единица.isEmpty) ? "" : ", " + поле.единица
        return ПодписьПоля(поле.подпись + единица, обязательно: поле.обязательно)
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
        VStack(alignment: .leading, spacing: 14) {
            КарточкаПодачи(т("aw_title"), подпись: т("aw_sub")) {
                марка
                if !модель.форма.бренд.isEmpty { модельАвто }
                if !поколения.isEmpty { поколение }
            }
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
        .task {
            await модель.загрузитьМарки()
            if модель.моделиАвто.isEmpty && !модель.форма.бренд.isEmpty {
                await модель.загрузитьМодели(модель.форма.бренд)
            }
        }
    }

    private var марка: some View {
        let ошибка = модель.ошибка("auto")
        return VStack(alignment: .leading, spacing: 6) {
            ПодписьПоля(т("aw_brand"), обязательно: true)
            СтрокаВыбора(модель.форма.бренд, подсказка: т("aw_brand_pick")) {
                выбратьМарку()
            }
            СтрокаОшибки(ошибка)
        }
        .id("auto")
    }

    private func выбратьМарку() {
        let м = модель
        фокус.wrappedValue = nil
        показатьСписок(СписокВыбора(заголовок: т("aw_brand"),
                                    варианты: м.маркиАвто.map { ВариантПоля(ключ: $0, подпись: $0) },
                                    своё: т("spec_other_write")) { марка in
            guard м.форма.бренд != марка else { return }
            var ф = м.форма
            ф.бренд = марка
            ф.модель = ""
            ф.поколение = ""
            м.форма = ф
            Task { await м.загрузитьМодели(марка) }
        })
    }

    private var модельАвто: some View {
        VStack(alignment: .leading, spacing: 6) {
            ПодписьПоля(т("aw_model"))
            СтрокаВыбора(модель.форма.модель, подсказка: т("spec_model")) {
                выбратьМодель()
            }
        }
    }

    private func выбратьМодель() {
        let м = модель
        фокус.wrappedValue = nil
        показатьСписок(СписокВыбора(заголовок: т("aw_model"),
                                    варианты: м.моделиАвто.map { ВариантПоля(ключ: $0.имя, подпись: $0.имя) },
                                    своё: т("spec_write_model")) { имя in
            var ф = м.форма
            ф.модель = имя
            ф.поколение = ""
            м.форма = ф
        })
    }

    private var поколение: some View {
        VStack(alignment: .leading, spacing: 6) {
            ПодписьПоля(т("aw_gen"))
            СтрокаВыбора(модель.форма.поколение, подсказка: т("spec_unset")) {
                выбратьПоколение()
            }
        }
    }

    private func выбратьПоколение() {
        let м = модель
        фокус.wrappedValue = nil
        var варианты: [ВариантПоля] = []
        for п in поколения {
            var подпись = п.имя
            if п.с > 0 {
                let до = п.по > 0 ? String(п.по) : т("aw_now")
                подпись += " · " + String(п.с) + "–" + до
            }
            варианты.append(ВариантПоля(ключ: п.имя, подпись: подпись))
        }
        показатьСписок(СписокВыбора(заголовок: т("aw_gen"), варианты: варианты, сброс: т("spec_unset")) { имя in
            м.форма.поколение = имя
        })
    }

    private var поколения: [ПоколениеАвто] {
        модель.моделиАвто.first(where: { $0.имя == модель.форма.модель })?.поколения ?? []
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
