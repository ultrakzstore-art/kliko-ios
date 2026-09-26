import SwiftUI
import PhotosUI
import UIKit

/**
 ПОДАЧА — ШАГИ «ФОТО», «ДАННЫЕ ТОВАРА», «ХАРАКТЕРИСТИКИ» И РАМКА ШАГОВ, ЭТАП 42 (владелец 26.09.2026).

 Рамка — addStepsSync сайта: полоса из семи отрезков (пройденные зелёные), «Фото · 1 / 7», внизу «Назад» и «Далее →».
 Шаг «Фото» — #photo-ecard: «Галерея», «Камера», плитки с загрузкой и «повторить», «главное», «Сделать главным»,
 «Удалить»; когда фото готовы — «Фото готовы — распознать?» (только по нажатию) и «Заполнить вручную». «Данные» —
 #add-card-data: название, каскад «— выберите раздел —» → «— категория —» → «— подкатегория —», бренд, описание.
 «Характеристики» — E_SPECS раздела, мастер недвижимости (REALTY_FIELDS), авто (/api/auto_models.php), запчастей
 (PARTS_FIELDS, /api/parts_types.php), VIN.
 */
struct ШагиПодачи: View {
    @ObservedObject var модель: ПодачаМодель
    let открытьСайт: (String) -> Void

    init(модель: ПодачаМодель, открытьСайт: @escaping (String) -> Void) {
        self.модель = модель
        self.открытьСайт = открытьСайт
    }

    private func т(_ ключ: String) -> String { ПодачаText.т(ключ) }

    var body: some View {
        VStack(spacing: 0) {
            полоса
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if модель.страница.нуженEgov && !модель.правка { плашкаEgov }
                    if !модель.правка { полосаТипа }
                    шаг
                }
                .padding(12)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            низ
        }
    }

    /// .add-steps: отрезки и «Название · N / 7».
    private var полоса: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(ШагПодачи.allCases) { ш in
                    Capsule()
                        .fill(ш.rawValue <= модель.шаг.rawValue ? Theme.зелёныйЯркий : Theme.линия)
                        .frame(height: 4)
                }
            }
            HStack {
                Text(модель.шаг.название)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                Spacer()
                Text(String(модель.шаг.rawValue + 1) + " / " + String(ШагПодачи.allCases.count))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
            }
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.поверхность)
    }

    /// #add-ver-bar: без верификации объявление ждёт в кабинете.
    private var плашкаEgov: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(т("ver_bar_t"))
                .font(.system(size: 14, weight: .bold))
            Text(т("ver_bar_s"))
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
            Button(т("ver_bar_go")) { открытьСайт("cabinet.php?go=verify") }
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
            Image(systemName: "square.grid.2x2")
                .foregroundStyle(Theme.акцент)
                .accessibilityHidden(true)
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
        case .данные: ШагДанные(модель: модель)
        case .характеристики: ШагХарактеристики(модель: модель)
        case .цена: ШагЦена(модель: модель)
        case .адрес: ШагАдрес(модель: модель)
        case .дополнительно: ШагДополнительно(модель: модель, открытьСайт: открытьСайт)
        case .проверка: ШагПроверка(модель: модель, открытьСайт: открытьСайт)
        }
    }

    /// .add-stepnav: «Назад» · «Далее →»; на «Проверке» — отправка. В правке «Сохранить изменения» — на каждом шаге.
    private var низ: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                if модель.шаг != .фото {
                    КнопкаПодачиВторая(т("back")) { модель.назад() }
                }
                if модель.шаг != .проверка {
                    КнопкаПодачи(т("next")) { модель.далее() }
                } else if !модель.правка {
                    КнопкаПодачи(кнопкаОтправки, занято: модель.отправляем) { модель.выставить() }
                }
            }
            if модель.правка {
                КнопкаПодачи(т(модель.отправляем ? "saving" : "edit_save"), занято: модель.отправляем) { модель.сохранить() }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Theme.поверхность)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.линия).frame(height: 1)
        }
    }

    private var кнопкаОтправки: String {
        if модель.отправляем { return т("sending") }
        return т(модель.форма.аренда && !модель.форма.тожеПродаю ? "form_submit_rent" : "form_submit") + " →"
    }
}

// MARK: - Фото

struct ШагФото: View {
    @ObservedObject var модель: ПодачаМодель
    @State private var выбор: [PhotosPickerItem] = []
    @State private var камера = false

    init(модель: ПодачаМодель) {
        self.модель = модель
    }

    private func т(_ ключ: String) -> String { ПодачаText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            КарточкаПодачи(т("form_add_photo"), подпись: String(format: т("form_photo_hint"), модель.лимитФото)) {
                if !модель.плитки.isEmpty { сетка }
                кнопки
                if модель.местоФото == 0 { ЗаметкаПодачи(String(format: т("photo_cap_full"), модель.лимитФото), тон: .внимание) }
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

    private var сетка: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(Array(модель.плитки.enumerated()), id: \.element.id) { номер, плитка in
                ПлиткаФотоВид(плитка: плитка, главная: номер == 0,
                              главной: { модель.сделатьГлавным(плитка.id) },
                              удалить: { модель.удалитьФото(плитка.id) },
                              повторить: { модель.повторить(плитка.id) })
            }
        }
    }

    private var кнопки: some View {
        HStack(spacing: 10) {
            PhotosPicker(selection: $выбор, maxSelectionCount: max(1, модель.местоФото), selectionBehavior: .ordered,
                         matching: .images) {
                Label(т("form_gallery"), systemImage: "photo.on.rectangle")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.акцент)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(Theme.оттенокАкцента, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            }
            .disabled(модель.местоФото == 0)
            if КамераПодачи.есть {
                Button {
                    камера = true
                } label: {
                    Label(т("form_camera"), systemImage: "camera")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Theme.зелёный, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(модель.местоФото == 0)
            }
        }
    }

    /// «Фото готовы — распознать?»: «Распознать» — POST recognize только по нажатию; «Заполнить вручную» — дальше.
    private var блокИИ: some View {
        КарточкаПодачи(т("rsh_done_t2"), подпись: т("rsh_done_ai_s")) {
            HStack(spacing: 10) {
                КнопкаПодачи(т("rsh_done_ai"), занято: модель.распознаём) { модель.распознать() }
                КнопкаПодачиВторая(т("form_manual")) { модель.далее() }
            }
            if let ии = модель.страница.состояние?.ии, ии.показать, !ии.оплачено || ии.лимит > 0 {
                Text(String(format: т("ai_left"), ии.осталось, ии.лимит))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
            }
        }
    }
}

/// Плитка фото (.photo-thumb): картинка, «главное», загрузка, ошибка с «повторить», меню действий.
struct ПлиткаФотоВид: View {
    let плитка: ПлиткаФото
    let главная: Bool
    let главной: () -> Void
    let удалить: () -> Void
    let повторить: () -> Void

    init(плитка: ПлиткаФото, главная: Bool, главной: @escaping () -> Void, удалить: @escaping () -> Void,
         повторить: @escaping () -> Void) {
        self.плитка = плитка
        self.главная = главная
        self.главной = главной
        self.удалить = удалить
        self.повторить = повторить
    }

    var body: some View {
        картинка
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            .overlay { состояние }
            .overlay(alignment: .topLeading) {
                if главная && плитка.готова {
                    Text(ПодачаText.т("main_photo"))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.зелёный, in: Capsule())
                        .padding(5)
                }
            }
            .overlay(alignment: .topTrailing) {
                Menu {
                    if !главная && плитка.готова {
                        Button(ПодачаText.т("make_main"), systemImage: "star") { главной() }
                    }
                    if плитка.ошибка != nil && плитка.картинка != nil {
                        Button(ПодачаText.т("retry_photo"), systemImage: "arrow.clockwise") { повторить() }
                    }
                    Button(ПодачаText.т("delete"), systemImage: "trash", role: .destructive) { удалить() }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 28, height: 28)
                        .background(Color.black.opacity(0.5), in: Circle())
                        .padding(4)
                }
                .accessibilityLabel(ПодачаText.т("photo_actions"))
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(главная ? ПодачаText.т("main_photo") : ПодачаText.т("photo"))
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
                Color.black.opacity(0.35)
                ProgressView()
                    .tint(Color.white)
            }
            .accessibilityLabel(ПодачаText.т("ph_prep_title"))
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
                    Button(ПодачаText.т("retry_photo")) { повторить() }
                        .font(.system(size: 11, weight: .bold))
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.зелёный)
                        .controlSize(.mini)
                }
            }
            .padding(4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.red.opacity(0.55))
        }
    }
}

// MARK: - Данные товара

struct ШагДанные: View {
    @ObservedObject var модель: ПодачаМодель
    @State private var список: СписокВыбора? = nil

    init(модель: ПодачаМодель) {
        self.модель = модель
    }

    private func т(_ ключ: String) -> String { ПодачаText.т(ключ) }

    var body: some View {
        КарточкаПодачи(т("step_what")) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    ПодписьПоля(т(модель.режим == .услуга ? "e_model_service" : "form_name"), обязательно: true)
                    if модель.заполненоИИ {
                        Text(т("form_ai_badge"))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.акцент)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.оттенокАкцента, in: Capsule())
                    }
                }
                ПолеПодачи(модель.режим == .авто ? т("auto_title_ph") : т("form_name_ph"), текст: $модель.форма.название,
                           заблокировано: модель.режим == .авто)
                if модель.режим == .авто {
                    Text(т("auto_title_hint"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            каскад
            if модель.брендВиден { бренд }
            VStack(alignment: .leading, spacing: 6) {
                ПодписьПоля(т("form_description"), обязательно: true)
                ТекстПодачи(т(модель.режим == .услуга ? "desc_ph_service" : "form_desc_ph"), текст: $модель.форма.описание)
            }
        }
        .sheet(item: $список) { с in
            ЛистВыбора(список: с)
        }
    }

    /// Каскад из трёх выборов (f-cat-l1 → l2 → l3): отправить можно раздел любого уровня (catApply на каждом).
    private var каскад: some View {
        let цепочка = модель.справочники.цепочка(модель.форма.раздел)
        let первый = цепочка.first ?? ""
        let второй = цепочка.count > 1 ? цепочка[1] : ""
        let третий = цепочка.count > 2 ? цепочка[цепочка.count - 1] : ""
        let детиПервого = модель.справочники.разделы[первый]?.дети ?? []
        let детиВторого = модель.справочники.разделы[второй]?.дети ?? []
        return VStack(alignment: .leading, spacing: 6) {
            ПодписьПоля(т("form_category"), обязательно: true)
            СтрокаВыбора(модель.справочники.имя(первый), подсказка: т("form_select_section")) {
                показатьРазделы(модель.справочники.корни, заголовок: т("form_select_section"))
            }
            if !первый.isEmpty && !детиПервого.isEmpty {
                СтрокаВыбора(модель.справочники.имя(второй), подсказка: т("cat_l2")) {
                    показатьРазделы(детиПервого, заголовок: т("cat_l2"))
                }
            }
            if !второй.isEmpty && !детиВторого.isEmpty {
                СтрокаВыбора(модель.справочники.имя(третий), подсказка: т("cat_l3")) {
                    показатьРазделы(детиВторого, заголовок: т("cat_l3"))
                }
            }
        }
    }

    private func показатьРазделы(_ ключи: [String], заголовок: String) {
        let варианты = ключи.map { ВариантПоля(ключ: $0, подпись: модель.справочники.имя($0)) }
        let м = модель
        список = СписокВыбора(заголовок: заголовок, варианты: варианты) { ключ in
            if !ключ.isEmpty { м.выбратьРаздел(ключ) }
        }
    }

    /// Бренд: список BRAND_LIST раздела с «Другой — вписать» или просто поле.
    private var бренд: some View {
        let бренды = модель.бренды
        return VStack(alignment: .leading, spacing: 6) {
            ПодписьПоля(т("form_brand"), необязательно: true)
            if бренды.isEmpty {
                ПолеПодачи(т("form_brand_ph"), текст: $модель.форма.бренд, заглавные: .words)
            } else {
                СтрокаВыбора(модель.форма.бренд, подсказка: т("form_brand_pick")) {
                    let м = модель
                    список = СписокВыбора(заголовок: т("form_brand"),
                                          варианты: бренды.map { ВариантПоля(ключ: $0, подпись: $0) },
                                          своё: т("form_brand_other"), сброс: т("spec_unset")) { значение in
                        м.форма.бренд = значение
                    }
                }
            }
        }
    }
}

// MARK: - Характеристики

struct ШагХарактеристики: View {
    @ObservedObject var модель: ПодачаМодель
    @State private var список: СписокВыбора? = nil

    init(модель: ПодачаМодель) {
        self.модель = модель
    }

    private func т(_ ключ: String) -> String { ПодачаText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch модель.режим {
            case .недвижимость:
                ПоляНедвижимости(модель: модель, показатьСписок: { с in список = с })
            case .авто:
                ПоляАвто(модель: модель, показатьСписок: { с in список = с })
            case .запчасти:
                ПоляЗапчасти(модель: модель, показатьСписок: { с in список = с })
            case .товар, .услуга, .работа:
                if !модель.характеристики.isEmpty { характеристики }
            }
            if модель.vinРазрешён { vin }
        }
        .sheet(item: $список) { с in
            ЛистВыбора(список: с)
        }
    }

    /// E_SPECS: список с «— не указано —» и «Другое (вписать)…» или числовое поле; пишется в cpu/gpu/ram/storage/year.
    private var характеристики: some View {
        КарточкаПодачи(т("form_specs")) {
            ForEach(модель.характеристики) { поле in
                VStack(alignment: .leading, spacing: 6) {
                    ПодписьПоля(поле.подпись)
                    if поле.варианты.isEmpty {
                        ПолеПодачи(поле.подпись, текст: значение(поле.поле), клавиатура: .numberPad)
                    } else {
                        СтрокаВыбора(значение(поле.поле).wrappedValue, подсказка: т("spec_unset")) {
                            let связь = значение(поле.поле)
                            список = СписокВыбора(заголовок: поле.подпись,
                                                  варианты: поле.варианты.map { ВариантПоля(ключ: $0, подпись: $0) },
                                                  своё: т("spec_other_write"), сброс: т("spec_unset")) { новое in
                                связь.wrappedValue = новое
                            }
                        }
                    }
                }
            }
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
                ПолеПодачи(т("vin_ph"), текст: vinСвязь, заглавные: .characters)
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
    let показатьСписок: (СписокВыбора) -> Void

    init(модель: ПодачаМодель, показатьСписок: @escaping (СписокВыбора) -> Void) {
        self.модель = модель
        self.показатьСписок = показатьСписок
    }

    private func т(_ ключ: String) -> String { ПодачаText.т(ключ) }

    var body: some View {
        КарточкаПодачи(т("as_realty"), подпись: модель.названиеНедвижимости()) {
            VStack(alignment: .leading, spacing: 6) {
                ПодписьПоля(т("as_rl_deal_q"))
                HStack(spacing: 8) {
                    ЧипПодачи(т("as_rl_sale"), выбран: модель.форма.сделка == "sale") { модель.форма.сделка = "sale" }
                    ЧипПодачи(т("as_rl_rent"), выбран: модель.форма.сделка == "rent") { модель.форма.сделка = "rent" }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                ПодписьПоля(т("as_rl_kind_q"))
                ПотокЧипов(зазор: 8) {
                    ЧипПодачи(т("rl_flat"), выбран: модель.форма.вид == "apartment") { сменитьВид("apartment") }
                    ЧипПодачи(т("rl_house"), выбран: модель.форма.вид == "house") { сменитьВид("house") }
                    ЧипПодачи(т("rl_office"), выбран: модель.форма.вид == "commercial") { сменитьВид("commercial") }
                    ЧипПодачи(т("rl_land"), выбран: модель.форма.вид == "land") { сменитьВид("land") }
                }
            }
            ForEach(модель.поляНедвижимости) { поле in
                ПолеМастераВид(поле: поле, значение: значение(поле.id), флаг: флаг(поле.id), варианты: поле.варианты,
                               показатьСписок: показатьСписок)
            }
        }
    }

    /// _rw2Pick: новый вид — поля заново, «Кто размещает» по умолчанию «Собственник».
    private func сменитьВид(_ вид: String) {
        guard модель.форма.вид != вид else { return }
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

/// Одно поле мастеров недвижимости и запчастей по его виду (chips · num · select · toggle · text · ptype).
struct ПолеМастераВид: View {
    let поле: ПолеМастера
    @Binding var значение: String
    @Binding var флаг: Bool
    let варианты: [ВариантПоля]
    let показатьСписок: (СписокВыбора) -> Void

    init(поле: ПолеМастера, значение: Binding<String>, флаг: Binding<Bool>, варианты: [ВариантПоля],
         показатьСписок: @escaping (СписокВыбора) -> Void) {
        self.поле = поле
        self._значение = значение
        self._флаг = флаг
        self.варианты = варианты
        self.показатьСписок = показатьСписок
    }

    var body: some View {
        switch поле.вид {
        case "toggle":
            ПереключательПодачи(поле.подпись, включено: $флаг)
        case "chips":
            VStack(alignment: .leading, spacing: 6) {
                ПодписьПоля(подпись)
                ПотокЧипов(зазор: 8) {
                    ForEach(варианты, id: \.self) { в in
                        ЧипПодачи(в.подпись, выбран: значение == в.ключ) {
                            значение = значение == в.ключ ? "" : в.ключ
                        }
                    }
                }
            }
        case "select", "ptype":
            VStack(alignment: .leading, spacing: 6) {
                ПодписьПоля(подпись)
                СтрокаВыбора(варианты.first(where: { $0.ключ == значение })?.подпись ?? значение,
                             подсказка: ПодачаText.т("spec_unset")) {
                    let связь = $значение
                    показатьСписок(СписокВыбора(заголовок: поле.подпись, варианты: варианты,
                                                сброс: ПодачаText.т("spec_unset")) { новое in
                        связь.wrappedValue = новое
                    })
                }
            }
        case "num":
            VStack(alignment: .leading, spacing: 6) {
                ПодписьПоля(подпись)
                ПолеПодачи(поле.единица.isEmpty ? поле.подпись : поле.единица, текст: числовое,
                           клавиатура: .decimalPad)
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                ПодписьПоля(подпись)
                ПолеПодачи(поле.подпись, текст: $значение)
            }
        }
    }

    private var подпись: String {
        (поле.подпись + (поле.единица.isEmpty ? "" : ", " + поле.единица)) + (поле.обязательно ? " *" : "")
    }

    /// Числа — только цифры и точка/запятая: «85 000 км» отбор витрины прочитал бы как ноль.
    private var числовое: Binding<String> {
        let связь = $значение
        return Binding(get: { связь.wrappedValue }, set: { новое in
            связь.wrappedValue = ПодачаМодель.дробное(новое)
        })
    }
}

/// Мастер авто (_aw2): марка → модель → поколение → год, пробег, объём → коробка и топливо.
struct ПоляАвто: View {
    @ObservedObject var модель: ПодачаМодель
    let показатьСписок: (СписокВыбора) -> Void

    init(модель: ПодачаМодель, показатьСписок: @escaping (СписокВыбора) -> Void) {
        self.модель = модель
        self.показатьСписок = показатьСписок
    }

    private func т(_ ключ: String) -> String { ПодачаText.т(ключ) }

    /// AW_GEAR и AW_FUEL сайта — «слова те же, что в фильтре витрины»: уходят по-русски на любом языке.
    private static let коробки = ["Автомат", "Механика", "Робот", "Вариатор"]
    private static let топливо = ["Бензин", "Дизель", "Газ", "Гибрид", "Электро"]

    var body: some View {
        КарточкаПодачи(т("aw_title"), подпись: т("aw_sub")) {
            VStack(alignment: .leading, spacing: 6) {
                ПодписьПоля(т("aw_brand"), обязательно: true)
                СтрокаВыбора(модель.форма.бренд, подсказка: т("aw_brand_pick")) {
                    let м = модель
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
            }
            if !модель.форма.бренд.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ПодписьПоля(т("aw_model"))
                    СтрокаВыбора(модель.форма.модель, подсказка: т("spec_model")) {
                        let м = модель
                        показатьСписок(СписокВыбора(заголовок: т("aw_model"),
                                                    варианты: м.моделиАвто.map { ВариантПоля(ключ: $0.имя, подпись: $0.имя) },
                                                    своё: т("spec_write_model")) { имя in
                            var ф = м.форма
                            ф.модель = имя
                            ф.поколение = ""
                            м.форма = ф
                        })
                    }
                }
            }
            if !поколения.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ПодписьПоля(т("aw_gen"))
                    СтрокаВыбора(модель.форма.поколение, подсказка: т("spec_unset")) {
                        let м = модель
                        let варианты = поколения.map { п -> ВариантПоля in
                            let годы = п.с > 0 ? " · " + String(п.с) + "–" + (п.по > 0 ? String(п.по) : т("aw_now")) : ""
                            return ВариантПоля(ключ: п.имя, подпись: п.имя + годы)
                        }
                        показатьСписок(СписокВыбора(заголовок: т("aw_gen"), варианты: варианты,
                                                    сброс: т("spec_unset")) { имя in
                            м.форма.поколение = имя
                        })
                    }
                }
            }
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    ПодписьПоля(т("aw_year"))
                    ПолеПодачи("2019", текст: цифры($модель.форма.year, предел: 4), клавиатура: .numberPad)
                }
                VStack(alignment: .leading, spacing: 6) {
                    ПодписьПоля(т("aw_mileage"))
                    ПолеПодачи("85000", текст: цифры($модель.форма.ram, предел: 7), клавиатура: .numberPad)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                ПодписьПоля(т("aw_engine"))
                ПолеПодачи("1.6", текст: объём, клавиатура: .decimalPad)
                Text(т("aw_nums_hint"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 6) {
                ПодписьПоля(т("aw_gear"))
                ПотокЧипов(зазор: 8) {
                    ForEach(Self.коробки, id: \.self) { к in
                        ЧипПодачи(к, выбран: модель.форма.cpu == к) {
                            модель.форма.cpu = модель.форма.cpu == к ? "" : к
                        }
                    }
                }
                ПодписьПоля(т("aw_fuel"))
                ПотокЧипов(зазор: 8) {
                    ForEach(Self.топливо, id: \.self) { к in
                        ЧипПодачи(к, выбран: модель.форма.gpu == к) {
                            модель.форма.gpu = модель.форма.gpu == к ? "" : к
                        }
                    }
                }
                Text(т("aw_words_hint"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task {
            await модель.загрузитьМарки()
            if модель.моделиАвто.isEmpty && !модель.форма.бренд.isEmpty {
                await модель.загрузитьМодели(модель.форма.бренд)
            }
        }
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
    let показатьСписок: (СписокВыбора) -> Void

    init(модель: ПодачаМодель, показатьСписок: @escaping (СписокВыбора) -> Void) {
        self.модель = модель
        self.показатьСписок = показатьСписок
    }

    var body: some View {
        КарточкаПодачи(ПодачаText.т("pw_title"), подпись: ПодачаText.т("pw_sub")) {
            ForEach(модель.поляЗапчасти) { поле in
                ПолеМастераВид(поле: поле, значение: значение(поле.id), флаг: флаг(поле.id),
                               варианты: поле.вид == "ptype" ? модель.типыЗапчастей : поле.варианты,
                               показатьСписок: показатьСписок)
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
