import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

/**
 ПОДАЧА С КАМЕРЫ (владелец, обход новичком: шапка обещает «Сфотографируйте — Kliko AI заполнит всё сам», значит и
 начинаем с камеры).

 Новое объявление: экран «Фото» (большая «Сфотографировать», «Выбрать из галереи», снимки, «Далее») → Kliko AI
 распознаёт (тот же recognize, что и раньше) → один экран «Проверьте»: название, цена, раздел («Не угадали? Выбрать
 раздел»), «Опубликовать». Характеристики, цена и состояние, адрес, оплата и доставка — свёрнуты в «Уточнить
 (необязательно)»; обязательное, чего не хватает (город, режим работы услуги, описание), встаёт на экран само.
 Транспорт, который определил Kliko AI, — мастер «Марка → Модель» с подставленной маркой; недвижимость — мастер объекта.
 «Без фото — выбрать раздел» — прежний «Что размещаете?» со всеми шагами (авто там — сначала марка и модель, услуги —
 мастер услуги, фото необязательно). Правка — прежние шаги целиком.
 */
extension ПодачаМодель {

    /// Обратно на экран фото (форма и снимки остаются).
    func кКамере() {
        guard !правка else { return }
        мастер = nil
        экран = .камера
    }

    /// «Без фото — выбрать раздел»: прежний «Что размещаете?» и полный путь по шагам.
    func безФото() {
        быстрый = false
        старт = .корень
        экран = .старт
    }

    /// PRO или магазин — им на экране фото видна ссылка «Перенести с другой площадки».
    var бизнесПодачи: Bool {
        МоиОбъявленияМодель.shared.массовые.про || страница.состояние?.магазин == true
    }

    /// «Далее» с экрана фото: короткий путь, «Проверьте» и Kliko AI (один раз; не доступен — сразу проверка).
    func начатьСФото() {
        guard !правка, !готовыеФото.isEmpty, !фотоГрузятся else { return }
        ошибкиПолей = [:]
        быстрый = true
        шаг = .проверка
        экран = .шаги
        запланироватьЧерновик()
        guard !быстроРаспознано else { return }
        if распознаваниеДоступно {
            распознать()
        } else {
            послеРаспознаванияБыстро()
        }
    }

    /**
     Kliko AI отработал (или недоступен): транспорт — мастер «Марка → Модель» с маркой от Kliko AI (модель он не
     называет, человек подтверждает или правит); недвижимость — мастер объекта один раз. Остальное — «Проверьте».
     */
    func послеРаспознаванияБыстро() {
        быстроРаспознано = true
        switch режим {
        case .авто:
            let марка = каноническаяМарка(форма.бренд)
            if марка != форма.бренд { форма.бренд = марка }
            открытьМастерПозже(.авто(кузов: false))
        case .недвижимость:
            guard !мастерНедвижимостиБыл else { return }
            мастерНедвижимостиБыл = true
            открытьМастерПозже(.недвижимость(сШага: 0))
        case .товар, .запчасти, .услуга, .работа:
            break
        }
    }

    /// «Не угадали? Выбрать раздел»: новый раздел; транспорт без модели и недвижимость — их мастер после листа.
    func выбратьРазделБыстро(_ ключ: String) {
        выбратьРаздел(ключ)
        var нужный: МастерПодачи? = nil
        switch режим {
        case .авто:
            if форма.модель.trimmingCharacters(in: .whitespaces).isEmpty { нужный = .авто(кузов: true) }
        case .недвижимость:
            if !мастерНедвижимостиБыл {
                мастерНедвижимостиБыл = true
                нужный = .недвижимость(сШага: 0)
            }
        case .товар, .запчасти, .услуга, .работа:
            break
        }
        guard let м = нужный else { return }
        // Лист разделов ещё уезжает — окно мастера после него.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard let модель = self, модель.экран == .шаги, модель.мастер == nil else { return }
            модель.мастер = м
        }
    }
}

// MARK: - Экран «Фото»

struct ЭкранКамерыПодачи: View {
    @ObservedObject var модель: ПодачаМодель
    let перенос: () -> Void
    let закрыть: () -> Void
    @State private var выбор: [PhotosPickerItem] = []
    @State private var камера = false
    @State private var тащим: UUID? = nil

    init(модель: ПодачаМодель, перенос: @escaping () -> Void, закрыть: @escaping () -> Void) {
        self.модель = модель
        self.перенос = перенос
        self.закрыть = закрыть
    }

    private func т(_ ключ: String) -> String { КамераПодачиText.т(ключ) }
    private func п(_ ключ: String) -> String { ПодачаText.т(ключ) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ГеройПодачи(правка: false, закрыть: закрыть)
                полоса
                    .padding(.top, 2)
                if модель.плитки.isEmpty {
                    пусто
                } else {
                    снимки
                }
                ссылки
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { низ }
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

    /// Полоса хода короткого пути: «Фото» — 1 из 2, дальше «Проверьте».
    private var полоса: some View {
        VStack(alignment: .leading, spacing: 8) {
            ПолосаШаговПодачи(всего: 2, текущий: 0)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(п("step_photo"))
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(КраскаПодачи.текст)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("1 / 2")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.текстВторой)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
    }

    /// Пусто: крупный значок, «Сфотографируйте вещь», что сделает Kliko AI, две большие кнопки.
    private var пусто: some View {
        VStack(spacing: 0) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 38, weight: .regular))
                .foregroundStyle(КраскаПодачи.хорошоТекст)
                .frame(width: 92, height: 92)
                .background(КраскаПодачи.хорошоФон, in: Circle())
                .accessibilityHidden(true)
            Text(т("cf_title"))
                .font(.title3.weight(.heavy))
                .foregroundStyle(КраскаПодачи.текст)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
                .accessibilityAddTraits(.isHeader)
            Text(т("cf_sub"))
                .font(.subheadline)
                .foregroundStyle(Theme.текстВторой)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            VStack(spacing: 10) {
                if КамераПодачи.есть {
                    Button { камера = true } label: {
                        ярлык(т("cf_shoot"), значок: "camera.fill", главная: true)
                    }
                    .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
                    галерея(главная: false)
                } else {
                    галерея(главная: true)
                }
            }
            .padding(.top, 22)
            Text(String(format: п("form_photo_hint"), модель.лимитФото))
                .font(.caption)
                .foregroundStyle(Theme.текстВторой)
                .padding(.top, 12)
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, minHeight: 380)
        .background(КраскаПодачи.карточка, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(КраскаПодачи.линия, lineWidth: 1)
        }
        .shadow(color: КраскаПодачи.тень, radius: 6, y: 2)
    }

    private func галерея(главная: Bool) -> some View {
        PhotosPicker(selection: $выбор, maxSelectionCount: max(1, модель.местоФото), selectionBehavior: .ordered,
                     matching: .images) {
            ярлык(т("cf_gallery"), значок: "photo.on.rectangle", главная: главная)
        }
        .buttonStyle(.plain)
    }

    /// Большая кнопка: главная — зелёный градиент с белым, вторая — мятная с зелёным текстом и кромкой.
    private func ярлык(_ подпись: String, значок: String, главная: Bool) -> some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
        return HStack(spacing: 10) {
            Image(systemName: значок)
                .font(.headline)
                .accessibilityHidden(true)
            Text(подпись)
                .font(.headline.weight(.bold))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(главная ? Color.white : КраскаПодачи.хорошоТекст)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 54)
        .background {
            if главная {
                форма.fill(LinearGradient(colors: [Theme.зелёный, Theme.зелёный2], startPoint: .topLeading,
                                          endPoint: .bottomTrailing))
            } else {
                форма.fill(КраскаПодачи.хорошоФон)
            }
        }
        .overlay {
            форма.strokeBorder(главная ? Color.clear : КраскаПодачи.хорошоТекст.opacity(0.35), lineWidth: 1.5)
        }
        .contentShape(форма)
    }

    /// Снимки есть: сетка (первое — обложка, перенос пальцем), «+», ещё снять или добавить из галереи.
    private var снимки: some View {
        КарточкаПодачи(п("step_photo"), подпись: подписьСнимков, значок: "camera") {
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
            }
            .onDrop(of: [UTType.text], delegate: КонецПереносаФото(тащим: $тащим))
            if модель.местоФото > 0 {
                HStack(spacing: 10) {
                    if КамераПодачи.есть {
                        Button { камера = true } label: {
                            ярлык(т("cf_shoot_more"), значок: "camera", главная: false)
                        }
                        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
                    }
                    галерея(главная: false)
                }
            } else {
                ПодсказкаПоля(String(format: п("photo_cap_full"), модель.лимитФото))
            }
        }
    }

    private var подписьСнимков: String {
        String(format: п("photo_count"), модель.плитки.count, модель.лимитФото) + " · " + п("photo_order_hint")
    }

    /// Мелкие ссылки под камерой: без фото — прежний выбор раздела; PRO и магазину — перенос с другой площадки.
    private var ссылки: some View {
        VStack(spacing: 2) {
            ссылка(т("cf_no_photo"), значок: "square.grid.2x2") { модель.безФото() }
            if модель.бизнесПодачи {
                ссылка(т("cf_import"), значок: "arrow.down.doc") { перенос() }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }

    private func ссылка(_ подпись: String, значок: String, действие: @escaping () -> Void) -> some View {
        Button(action: действие) {
            Label(подпись, systemImage: значок)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(КраскаПодачи.хорошоТекст)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Низ — только когда снимки есть: «Далее» (с Kliko AI — «Далее — Kliko AI заполнит»); пока грузятся — ждём.
    @ViewBuilder
    private var низ: some View {
        let грузятся = модель.фотоГрузятся
        let можно = !модель.готовыеФото.isEmpty && !грузятся
        if !модель.плитки.isEmpty {
            VStack(spacing: 6) {
                if грузятся {
                    Text(т("cf_uploading"))
                        .font(.footnote)
                        .foregroundStyle(Theme.текстВторой)
                } else if модель.готовыеФото.isEmpty {
                    Text(т("cf_need_photo"))
                        .font(.footnote)
                        .foregroundStyle(Theme.текстВторой)
                }
                КнопкаДалееПодачи(подписьДалее) { модель.начатьСФото() }
                    .disabled(!можно)
                    .opacity(можно ? 1 : 0.5)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(КраскаПодачи.фон.ignoresSafeArea(edges: .bottom))
        }
    }

    private var подписьДалее: String {
        if модель.распознаваниеДоступно && !модель.быстроРаспознано { return т("cf_next_ai") }
        return п("next")
    }
}

// MARK: - «Проверьте»

/// Короткий экран после Kliko AI: снимки, название, раздел, цена; «Уточнить (необязательно)» — свёрнутые шаги.
struct ПроверкаКамерыПодачи: View {
    @ObservedObject var модель: ПодачаМодель
    let фокус: FocusState<String?>.Binding
    let открытьАдрес: (String) -> Void
    @State private var разделы = false
    @State private var раскрыто: Set<ШагПодачи> = []
    /// Описание короткое (Kliko AI не написал) или с ошибкой — поле на экране, пока идёт подача.
    @State private var описаниеВидно = false
    /// Город не указан или услуге нужен режим работы — карточка адреса на экране, а не в «Уточнить».
    @State private var адресВиден = false

    init(модель: ПодачаМодель, фокус: FocusState<String?>.Binding, открытьАдрес: @escaping (String) -> Void) {
        self.модель = модель
        self.фокус = фокус
        self.открытьАдрес = открытьАдрес
    }

    private func т(_ ключ: String) -> String { КамераПодачиText.т(ключ) }
    private func п(_ ключ: String) -> String { ПодачаText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            лента
            if let статус = модель.статусИИ {
                ЗаметкаПодачи(статус, тон: модель.заполненоИИ ? .хорошо : .внимание, значок: "sparkles")
            }
            главное
            if адресВиден {
                ШагАдрес(модель: модель, фокус: фокус)
            }
            уточнить
            КнопкаПодробнееПодачи { модель.подробнееПоШагам() }
        }
        .sheet(isPresented: $разделы) {
            ЛистРазделов(справочники: модель.справочники, выбрано: модель.форма.раздел, выбрать: { ключ in
                модель.выбратьРазделБыстро(ключ)
            })
        }
        .onAppear {
            if !модель.распознаём { отметитьНужное() }
        }
        .onChange(of: модель.распознаём) { _, идёт in
            if !идёт { отметитьНужное() }
        }
        .onChange(of: модель.ошибкиПолей) { _, _ in отметитьНужное() }
        .onChange(of: модель.форма.раздел) { _, _ in
            if модель.ошибкаЧасов() != nil { адресВиден = true }
        }
    }

    /// Обязательное, чего не хватает, — на экран (однажды показанное не прячется, пока человек его заполняет).
    private func отметитьНужное() {
        let описание = модель.форма.описание.trimmingCharacters(in: .whitespacesAndNewlines)
        if описание.count < 10 || модель.ошибка("desc") != nil { описаниеВидно = true }
        let город = модель.форма.город.trimmingCharacters(in: .whitespacesAndNewlines)
        if город.isEmpty || модель.ошибка("city") != nil || модель.ошибка("hours") != nil || модель.ошибкаЧасов() != nil {
            адресВиден = true
        }
        if модель.ошибка("price") != nil && модель.форма.аренда { раскрыто.insert(.цена) }
        /* Обязательная марка или поле схемы не заполнены — «Характеристики» раскрываются, строка ошибки под полем. */
        if модель.ошибкиПолей.keys.contains(where: { $0 == "brand" || $0.hasPrefix("sp_") }) {
            раскрыто.insert(.характеристики)
        }
    }

    // MARK: Снимки

    /// Ряд миниатюр и «Изменить фото» — обратно на экран фото.
    private var лента: some View {
        HStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(модель.плитки) { плитка in
                        МиниФотоПроверки(плитка: плитка)
                    }
                }
                .padding(.vertical, 2)
            }
            Button { модель.кКамере() } label: {
                VStack(spacing: 4) {
                    Image(systemName: "camera")
                        .font(.headline)
                        .accessibilityHidden(true)
                    Text(т("cf_edit_photos"))
                        .font(.caption.weight(.bold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                .foregroundStyle(КраскаПодачи.хорошоТекст)
                .frame(width: 84, height: 64)
                .background(КраскаПодачи.хорошоФон, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
        }
    }

    // MARK: Главное: название, раздел, цена

    private var главное: some View {
        КарточкаПодачи(т("cf_review_card"), значок: "checkmark.seal") {
            параметры
            if модель.режим != .авто { название }
            раздел
            if !раскрыто.contains(.цена) && !модель.форма.аренда { цена }
            if описаниеВидно { описание }
        }
    }

    /// Транспорт — карточка «Марка и модель» (мастер), недвижимость — карточка объекта.
    @ViewBuilder
    private var параметры: some View {
        let тм = МастерПодачиText.т
        let есть = !модель.форма.бренд.trimmingCharacters(in: .whitespaces).isEmpty
        let сводка = модель.сводкаНедвижимости
        switch модель.режим {
        case .авто:
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
        case .недвижимость:
            ВходМастераПодачи(значок: "house", заголовок: сводка.заголовок, подпись: сводка.подпись,
                              заполнено: !модель.форма.вид.isEmpty && !модель.форма.недвижимость.isEmpty) {
                фокус.wrappedValue = nil
                модель.открытьМастерНедвижимости()
            }
        case .товар, .запчасти, .услуга, .работа:
            EmptyView()
        }
    }

    private var название: some View {
        let ошибка = модель.ошибка("title")
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ПодписьПоля(п(модель.режим == .услуга ? "e_model_service" : "form_name"))
                if модель.заполненоИИ {
                    Text(п("form_ai_badge"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(КраскаПодачи.хорошоТекст)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(КраскаПодачи.хорошоФон, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            ПолеПодачи(п("form_name_ph"), текст: $модель.форма.название, фокус: фокус, ключ: "title",
                       ошибка: ошибка != nil, предел: ПределыПодачи.название, счётчик: true)
            СтрокаОшибки(ошибка)
        }
    }

    /// Раздел, который выбрал Kliko AI, и «Не угадали? Выбрать раздел» — лист разделов с поиском.
    private var раздел: some View {
        let ошибка = модель.ошибка("category")
        let пусто = модель.форма.раздел.isEmpty
        return VStack(alignment: .leading, spacing: 8) {
            ПодписьПоля(п("form_category"))
            СтрокаРазделаПодачи(справочники: модель.справочники, раздел: модель.форма.раздел, ошибка: ошибка != nil) {
                открытьРазделы()
            }
            СтрокаОшибки(ошибка)
            ПодсказкаРазделаПодачи(модель: модель)
            Button { открытьРазделы() } label: {
                Text(т(пусто ? "cf_pick_cat" : "cf_wrong_cat"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(КраскаПодачи.хорошоТекст)
                    .underline()
                    .frame(minHeight: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .id("category")
    }

    private func открытьРазделы() {
        фокус.wrappedValue = nil
        разделы = true
    }

    /// Цена: поле с «₸», подсказка Kliko AI или рынка (Срочно / Рынок / Высокая), «Торг» («Договорная» у услуг).
    private var цена: some View {
        let услуга = модель.услугаИлиРабота
        let ошибка = модель.ошибка("price")
        return VStack(alignment: .leading, spacing: 8) {
            ПодписьПоля(п("form_your_price"), необязательно: услуга)
            ПолеЦены(текст: ценаСвязь, заблокировано: услуга && модель.форма.торг, ошибка: ошибка != nil,
                     фокус: фокус, ключ: "price")
            СтрокаОшибки(ошибка)
            if let подсказка = модель.подсказкаЦены { якоря(подсказка) }
            if let рынок = модель.рынок {
                ЗаметкаПодачи(рынок, тон: модель.рынокДорого ? .внимание : .хорошо, значок: "chart.line.uptrend.xyaxis")
            }
            ПереключательПодачи(п(услуга ? "price_negotiable" : "form_bargain"), включено: торгСвязь)
        }
    }

    private var ценаСвязь: Binding<String> {
        let м = модель
        return Binding(get: {
            let число = Int(м.форма.цена) ?? 0
            return число > 0 ? ПодачаМодель.деньги(число) : ""
        }, set: { новое in
            let цифры = ПодачаМодель.цифры(новое)
            if цифры != м.форма.цена { м.форма.цена = цифры }
        })
    }

    private var торгСвязь: Binding<Bool> {
        let м = модель
        return Binding(get: { м.форма.торг }, set: { новое in
            м.форма.торг = новое
            if новое && м.услугаИлиРабота { м.форма.цена = "" }
        })
    }

    private func якоря(_ подсказка: ПодсказкаЦены) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(п("form_price_hint") + " · " + подсказка.подпись)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.текстВторой)
            HStack(spacing: 8) {
                якорь(п("form_price_urgent"), подсказка.низ)
                якорь(п("form_price_market"), подсказка.середина)
                якорь(п("form_price_high"), подсказка.верх)
            }
        }
    }

    private func якорь(_ подпись: String, _ цена: Int) -> some View {
        let выбран = модель.ценаЧислом == цена && цена > 0
        return Button {
            модель.форма.цена = String(цена)
            ОткликСайта.выбор()
        } label: {
            VStack(spacing: 2) {
                Text(подпись)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.текстВторой)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(ПодачаМодель.деньги(цена) + " ₸")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(выбран ? Theme.акцент : Theme.текст)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(выбран ? КраскаПодачи.хорошоФон : КраскаПодачи.поле,
                        in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                    .strokeBorder(выбран ? КраскаПодачи.акцентТекст : КраскаПодачи.линия, lineWidth: выбран ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(выбран ? .isSelected : [])
    }

    /// Описание (от 10 знаков — как у сайта): на экране, когда Kliko AI его не написал или человек открыл сам.
    private var описание: some View {
        let ошибка = модель.ошибка("desc")
        let длина = модель.форма.описание.count
        return VStack(alignment: .leading, spacing: 6) {
            ПодписьПоля(п("form_description"), обязательно: true, мелкая: true)
            ТекстПодачи(п(модель.режим == .услуга ? "desc_ph_service" : "form_desc_ph"), текст: $модель.форма.описание,
                        фокус: фокус, ключ: "desc", ошибка: ошибка != nil)
            HStack(alignment: .top, spacing: 8) {
                if ошибка != nil {
                    СтрокаОшибки(ошибка)
                } else {
                    ПодсказкаПоля(п("desc_min"))
                }
                Spacer(minLength: 0)
                Text(String(длина) + " / 5000")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.текстВторой)
                    .accessibilityHidden(true)
            }
        }
    }

    // MARK: «Уточнить (необязательно)»

    private var шагиУточнить: [ШагПодачи] {
        var ш: [ШагПодачи] = []
        if модель.виден(.характеристики) { ш.append(.характеристики) }
        ш.append(.цена)
        if !адресВиден { ш.append(.адрес) }
        if модель.виден(.дополнительно) { ш.append(.дополнительно) }
        return ш
    }

    private var уточнить: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(т("cf_more"))
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(КраскаПодачи.текст)
                    .accessibilityAddTraits(.isHeader)
                Text(т("cf_more_s"))
                    .font(.footnote)
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
            ForEach(шагиУточнить) { ш in
                строка(ш.id, значок: ШагПодачи.значок(ш), заголовок: заголовок(ш), сводка: модель.сводка(ш),
                       открыто: раскрыто.contains(ш)) {
                    переключить(ш)
                }
                if раскрыто.contains(ш) { содержимое(ш) }
            }
            if !описаниеВидно {
                строка(100, значок: "text.alignleft", заголовок: т("cf_desc"), сводка: сводкаОписания, открыто: false) {
                    withAnimation(ДвижениеСайта.смена) { описаниеВидно = true }
                    фокус.wrappedValue = "desc"
                }
            }
        }
    }

    private func заголовок(_ ш: ШагПодачи) -> String {
        ш == .дополнительно ? т("cf_extra") : ш.название
    }

    private var сводкаОписания: String {
        let текст = модель.форма.описание.trimmingCharacters(in: .whitespacesAndNewlines)
        if текст.isEmpty { return п("rv_empty") }
        return текст.count > 60 ? String(текст.prefix(60)) + "…" : текст
    }

    private func переключить(_ ш: ШагПодачи) {
        фокус.wrappedValue = nil
        withAnimation(ДвижениеСайта.смена) {
            if раскрыто.contains(ш) {
                раскрыто.remove(ш)
            } else {
                раскрыто.insert(ш)
            }
        }
    }

    @ViewBuilder
    private func содержимое(_ ш: ШагПодачи) -> some View {
        switch ш {
        case .характеристики: ШагХарактеристики(модель: модель, фокус: фокус)
        case .цена: ШагЦена(модель: модель, фокус: фокус)
        case .адрес: ШагАдрес(модель: модель, фокус: фокус)
        case .дополнительно: ШагДополнительно(модель: модель, фокус: фокус, открытьАдрес: открытьАдрес)
        case .фото, .данные, .проверка: EmptyView()
        }
    }

    /// Строка свёрнутого шага: значок, название, что уже заполнено, стрелка.
    private func строка(_ номер: Int, значок: String, заголовок: String, сводка: String, открыто: Bool,
                        действие: @escaping () -> Void) -> some View {
        Button(action: действие) {
            HStack(spacing: 12) {
                Image(systemName: значок)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(КраскаПодачи.хорошоТекст)
                    .frame(width: 34, height: 34)
                    .background(КраскаПодачи.хорошоФон, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(заголовок)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(КраскаПодачи.текст)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(сводка)
                        .font(.caption)
                        .foregroundStyle(Theme.текстВторой)
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                Image(systemName: открыто ? "chevron.up" : "chevron.down")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.текстВторой)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(КраскаПодачи.карточка, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                    .strokeBorder(КраскаПодачи.линия, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
        .accessibilityAddTraits(открыто ? .isSelected : [])
        .id("more_" + String(номер))
    }
}

/// Миниатюра снимка на «Проверьте»: превью с телефона или загруженное фото; пока грузится — колёсико.
struct МиниФотоПроверки: View {
    let плитка: ПлиткаФото

    init(плитка: ПлиткаФото) {
        self.плитка = плитка
    }

    var body: some View {
        картинка
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .overlay {
                if плитка.грузится {
                    ZStack {
                        Color.black.opacity(0.35)
                        ProgressView().tint(Color.white)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                    .strokeBorder(КраскаПодачи.линия, lineWidth: 1)
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var картинка: some View {
        if let превью = плитка.превью {
            Image(uiImage: превью)
                .resizable()
                .scaledToFill()
        } else if let адрес = Config.url(плитка.url) {
            /* Адрес фото сервера — только картинка, нажатием не открывается. */
            AsyncImage(url: адрес) { фаза in
                if let изображение = фаза.image {
                    изображение.resizable().scaledToFill()
                } else {
                    Theme.поверхность2
                }
            }
        } else {
            Theme.поверхность2
        }
    }
}

// MARK: - Тексты (ru / kk / en / ar)

enum КамераПодачиText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь: [String: String]
        switch язык {
        case "kk": словарь = kk
        case "en": словарь = en
        case "ar": словарь = ar
        default: словарь = ru
        }
        return словарь[ключ] ?? ru[ключ] ?? ПодачаText.т(ключ)
    }

    private static let ru: [String: String] = [
        "cf_title": "Сфотографируйте вещь",
        "cf_sub": "Kliko AI сам определит раздел, заполнит название и подскажет цену — вам останется проверить",
        "cf_shoot": "Сфотографировать", "cf_shoot_more": "Ещё снимок", "cf_gallery": "Выбрать из галереи",
        "cf_no_photo": "Без фото — выбрать раздел", "cf_import": "Перенести с другой площадки",
        "cf_uploading": "Загружаем фото…", "cf_need_photo": "Добавьте хотя бы одно фото",
        "cf_next_ai": "Далее — Kliko AI заполнит", "cf_edit_photos": "Изменить фото",
        "cf_review": "Проверьте", "cf_review_card": "Проверьте и опубликуйте",
        "cf_wrong_cat": "Не угадали? Выбрать раздел", "cf_pick_cat": "Выберите раздел",
        "cf_more": "Уточнить (необязательно)", "cf_more_s": "Можно пропустить — это видно покупателям, но не обязательно",
        "cf_extra": "Оплата, доставка, гарантии", "cf_desc": "Описание"
    ]

    private static let kk: [String: String] = [
        "cf_title": "Затты суретке түсіріңіз",
        "cf_sub": "Kliko AI бөлімді өзі анықтап, атауын толтырады және бағасын ұсынады — сізге тек тексеру қалады",
        "cf_shoot": "Суретке түсіру", "cf_shoot_more": "Тағы түсіру", "cf_gallery": "Галереядан таңдау",
        "cf_no_photo": "Суретсіз — бөлімді таңдау", "cf_import": "Басқа алаңнан көшіру",
        "cf_uploading": "Суреттер жүктелуде…", "cf_need_photo": "Кемінде бір сурет қосыңыз",
        "cf_next_ai": "Әрі қарай — Kliko AI толтырады", "cf_edit_photos": "Суретті өзгерту",
        "cf_review": "Тексеріңіз", "cf_review_card": "Тексеріп, жариялаңыз",
        "cf_wrong_cat": "Дұрыс емес пе? Бөлімді таңдау", "cf_pick_cat": "Бөлімді таңдаңыз",
        "cf_more": "Нақтылау (міндетті емес)", "cf_more_s": "Өткізіп жіберуге болады — сатып алушыларға көрінеді, бірақ міндетті емес",
        "cf_extra": "Төлем, жеткізу, кепілдік", "cf_desc": "Сипаттама"
    ]

    private static let en: [String: String] = [
        "cf_title": "Take a photo of your item",
        "cf_sub": "Kliko AI will pick the category, fill in the title and suggest a price — you just check it",
        "cf_shoot": "Take a photo", "cf_shoot_more": "Another photo", "cf_gallery": "Choose from gallery",
        "cf_no_photo": "No photo — choose a category", "cf_import": "Move from another marketplace",
        "cf_uploading": "Uploading photos…", "cf_need_photo": "Add at least one photo",
        "cf_next_ai": "Next — Kliko AI fills it in", "cf_edit_photos": "Edit photos",
        "cf_review": "Check", "cf_review_card": "Check and publish",
        "cf_wrong_cat": "Wrong guess? Choose a category", "cf_pick_cat": "Choose a category",
        "cf_more": "Add details (optional)", "cf_more_s": "You can skip this — buyers will see it, but it isn't required",
        "cf_extra": "Payment, delivery, warranty", "cf_desc": "Description"
    ]

    private static let ar: [String: String] = [
        "cf_title": "صوّر غرضك",
        "cf_sub": "سيحدد Kliko AI القسم ويملأ العنوان ويقترح السعر — ما عليك إلا المراجعة",
        "cf_shoot": "التقط صورة", "cf_shoot_more": "صورة أخرى", "cf_gallery": "اختر من المعرض",
        "cf_no_photo": "بدون صورة — اختر القسم", "cf_import": "انقل من منصة أخرى",
        "cf_uploading": "جارٍ رفع الصور…", "cf_need_photo": "أضف صورة واحدة على الأقل",
        "cf_next_ai": "التالي — Kliko AI سيملؤه", "cf_edit_photos": "تعديل الصور",
        "cf_review": "راجِع", "cf_review_card": "راجِع وانشر",
        "cf_wrong_cat": "لم يُصب؟ اختر القسم", "cf_pick_cat": "اختر القسم",
        "cf_more": "تفاصيل إضافية (اختياري)", "cf_more_s": "يمكنك التخطي — يراها المشترون لكنها غير إلزامية",
        "cf_extra": "الدفع والتوصيل والضمان", "cf_desc": "الوصف"
    ]
}
