import SwiftUI

/**
 ПОЛНОЭКРАННЫЙ ПОИСК КАК НА САЙТЕ — #mk-search-ov (владелец 26.09.2026, TestFlight 1.10: «поисковик не такой же как на
 сайте — нужно чтобы такой же с подсказкой»).

 На телефоне сайт не даёт печатать в #mk-q шапки: касание поля (onfocus/onclick → mkSearchOpen) открывает поверх всего
 белый экран поиска — сверху «←», поле «Поиск по объявлениям» с лупой и «×», справа камера (.mk-sov-top), под ним —
 подсказки mkSovRender (ПодсказкиСайта). Здесь — то же: поле шапки получило фокус — открывается этот экран, фокус — в
 его поле (через 70 мс, как setTimeout сайта), с тем, что было набрано в шапке.

 Что делает нажатие — mkSovPick и _mkSovBind:
 • строка запроса, подсказка, прежний или популярный запрос, «Найти» на клавиатуре — запрос наверх «Вы искали»
   (mk_recent; здесь — RecentStore), экран закрывается, лента ищет (mkSearch); пустой запрос — просто закрыть;
 • раздел — экран закрывается, лента открывает раздел (mkCat), набранное не отправляется;
 • бренд — раздел бренда и имя бренда запросом (ulxBrandGo);
 • «↖» у подсказки — вставить её в поле и искать дальше (mkSovFill), «×» у «Вы искали» — забыть запрос, «Очистить» —
   забыть все;
 • камера — экран закрывается, открывается поиск по фото (mkSearchClose(); mkPhotoSearch()).
 Задержки перед подсказками нет — у сайта её тоже нет: список строится на каждый ввод, без запроса к серверу.
 */
struct ДействияПоискаСайта {
    /// Отправить запрос в ленту (mkSearch).
    let найти: (String) -> Void
    /// Открыть раздел (mkCat / mkSubcat).
    let раздел: (String) -> Void
    /// Раздел бренда и бренд запросом (ulxBrandGo): раздел, бренд.
    let бренд: (String, String) -> Void
    /// Распознали фото: запрос, раздел (пусто — без раздела).
    let фото: (String, String) -> Void
}

/// Вешается на ленту: поле шапки в фокусе — экран поиска; итог поиска по фото — в ленту; плашка «Ищем: …».
struct ПоискКакНаСайте: ViewModifier {
    let текст: String
    let фокус: FocusState<Bool>.Binding
    let товары: [Listing]
    let открыть: (URL) -> Void
    let действия: ДействияПоискаСайта

    @State private var показан = false
    /// Камеру нажали на экране поиска — поиск по фото после того, как экран закроется.
    @State private var фотоПотом = false
    @ObservedObject private var фото = ПоискПоФотоСайта.shared

    init(текст: String, фокус: FocusState<Bool>.Binding, товары: [Listing], открыть: @escaping (URL) -> Void,
         действия: ДействияПоискаСайта) {
        self.текст = текст
        self.фокус = фокус
        self.товары = товары
        self.открыть = открыть
        self.действия = действия
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: фокус.wrappedValue) { _, вФокусе in
                guard вФокусе, !показан else { return }
                фокус.wrappedValue = false
                сменить(true)
            }
            .fullScreenCover(isPresented: $показан, onDismiss: {
                guard фотоПотом else { return }
                фотоПотом = false
                фото.начать()
            }) {
                ЭкранПоискаСайта(начальный: текст, товары: товары, закрыть: { сменить(false) },
                                 найти: { запрос in
                                     сменить(false)
                                     действия.найти(запрос)
                                 },
                                 раздел: { ключ in
                                     сменить(false)
                                     действия.раздел(ключ)
                                 },
                                 бренд: { ключ, имя in
                                     сменить(false)
                                     действия.бренд(ключ, имя)
                                 },
                                 камера: {
                                     фотоПотом = true
                                     сменить(false)
                                 })
            }
            .background {
                СлойПоискаПоФото(модель: фото, открыть: открыть)
            }
            .onChange(of: фото.итог) { _, итог in
                guard let итог else { return }
                действия.фото(итог.запрос, итог.раздел)
            }
            .overlay(alignment: .bottom) {
                if let плашка = фото.плашка {
                    ПлашкаПоиска(текст: плашка)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 90)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
            .animation(ДвижениеСайта.смена, value: фото.плашка)
    }

    /// Экран поиска появляется и уходит без выезда снизу — у сайта он просто проявляется (.mk-sov.open, 0,18 с).
    private func сменить(_ стало: Bool) {
        var переход = Transaction()
        переход.disablesAnimations = true
        withTransaction(переход) { показан = стало }
    }
}

/// Плашка внизу — toast сайта (.mk-toast: --mk-ink с текстом --mk-surf, 13 px/600, поля 12 20, скругление 12).
private struct ПлашкаПоиска: View {
    let текст: String

    var body: some View {
        Text(текст)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.поверхность)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Theme.текст, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .shadow(color: Color.black.opacity(0.22), radius: 12, x: 0, y: 8)
    }
}

/// Экран #mk-search-ov: верхняя полоса .mk-sov-top и список .mk-sov-body.
struct ЭкранПоискаСайта: View {
    let начальный: String
    let товары: [Listing]
    let закрыть: () -> Void
    let найти: (String) -> Void
    let раздел: (String) -> Void
    let бренд: (String, String) -> Void
    let камера: () -> Void

    @State private var текст: String
    @State private var каталог = КаталогПоиска()
    @FocusState private var вФокусе: Bool
    @ObservedObject private var недавние = RecentStore.shared
    @State private var появился = false

    init(начальный: String, товары: [Listing], закрыть: @escaping () -> Void, найти: @escaping (String) -> Void,
         раздел: @escaping (String) -> Void, бренд: @escaping (String, String) -> Void,
         камера: @escaping () -> Void) {
        self.начальный = начальный
        self.товары = товары
        self.закрыть = закрыть
        self.найти = найти
        self.раздел = раздел
        self.бренд = бренд
        self.камера = камера
        _текст = State(initialValue: начальный)
    }

    private func т(_ ключ: String) -> String { ПоискСайтаText.т(ключ) }

    private var прежние: [String] { Config.недавние ? недавние.запросы : [] }

    var body: some View {
        let выдача = ПодсказкиСайта.выдача(текст, каталог: каталог, недавние: прежние, товары: товары)
        return VStack(spacing: 0) {
            верх
            ScrollView {
                СписокПодсказок(выдача: выдача, выбратьЗапрос: { запрос in выбрать(запрос) },
                                вставить: { запрос in вставить(запрос) },
                                забыть: { запрос in недавние.забытьЗапрос(запрос) },
                                очистить: { недавние.очиститьЗапросы() },
                                раздел: раздел, бренд: бренд)
                    .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Theme.поверхность.ignoresSafeArea())
        .opacity(появился ? 1 : 0)
        .offset(y: появился ? 0 : -6)
        .onAppear {
            withAnimation(ДвижениеСайта.появление) { появился = true }
        }
        .task {
            /* Как setTimeout(…focus, 70) у сайта: поле получает фокус, когда экран уже на месте. */
            try? await Task.sleep(nanoseconds: 70_000_000)
            вФокусе = true
            каталог = await ЗагрузкаКаталогаПоиска.получить()
        }
    }

    /// .mk-sov-top: «←» 40 pt, поле (.mk-sov-field) и камера 40 pt зелёным; снизу — линия.
    private var верх: some View {
        HStack(spacing: 8) {
            Button(action: закрыть) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Theme.текст)
                    .flipsForRightToLeftLayoutDirection(true)
                    .frame(width: 40, height: 40)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(т("back"))
            поле
            Button(action: камера) {
                Image(systemName: "camera")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Theme.зелёный2)
                    .frame(width: 40, height: 40)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(т("cam"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.поверхность)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.линия)
                .frame(height: 1)
                .accessibilityHidden(true)
        }
    }

    /// Поле: подложка surf2 и рамка 1,5 pt линии, в фокусе — поверхность и рамка зелёным (:focus-within).
    private var поле: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.текстВторой)
                .accessibilityHidden(true)
            TextField(т("placeholder"), text: $текст,
                      prompt: Text(т("placeholder")).foregroundColor(Theme.текстВторой))
                .font(.system(size: 16))
                .foregroundStyle(Theme.текст)
                .tint(Theme.акцент)
                .focused($вФокусе)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit { выбрать(текст) }
            if !текст.isEmpty {
                Button {
                    текст = ""
                    вФокусе = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.текстВторой)
                        .frame(width: 28, height: 28)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(т("clear_field"))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .background(вФокусе ? Theme.поверхность : Theme.поверхность2,
                    in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                .strokeBorder(вФокусе ? Theme.зелёный2 : Theme.линия, lineWidth: 1.5)
        }
    }

    /// mkSovPick: пустое — закрыть; иначе — в «Вы искали» и искать.
    private func выбрать(_ запрос: String) {
        let чистый = запрос.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !чистый.isEmpty else {
            закрыть()
            return
        }
        if Config.недавние { недавние.запомнитьЗапрос(чистый) }
        найти(чистый)
    }

    /// mkSovFill: подсказку — в поле, фокус остаётся, список — по ней.
    private func вставить(_ запрос: String) {
        текст = запрос
        вФокусе = true
    }
}

/// .mk-sov-body: секции и строки в порядке mkSovRender.
private struct СписокПодсказок: View {
    let выдача: ПодсказкиСайта.Выдача
    let выбратьЗапрос: (String) -> Void
    let вставить: (String) -> Void
    let забыть: (String) -> Void
    let очистить: () -> Void
    let раздел: (String) -> Void
    let бренд: (String, String) -> Void

    private func т(_ ключ: String) -> String { ПоискСайтаText.т(ключ) }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            if выдача.набрано.isEmpty {
                пустоеПоле
            } else {
                набрано
            }
        }
        .padding(.horizontal, 8)            // список сайта отступает на 8: значки строк — на 20, разделов — на 16
    }

    @ViewBuilder
    private var пустоеПоле: some View {
        if !выдача.недавние.isEmpty {
            Заголовок(текст: т("sov_recent"), кнопка: т("sov_clear"), действие: очистить)
            ForEach(выдача.недавние, id: \.self) { строка in
                СтрокаЗапроса(строка: строка, выбрать: выбратьЗапрос, сбоку: { забыть(строка.текст) })
            }
        }
        if !выдача.популярные.isEmpty {
            Заголовок(текст: т("sov_trending"), кнопка: nil, действие: nil)
            ForEach(выдача.популярные, id: \.self) { популярный in
                switch популярный {
                case .раздел(let найденный):
                    СтрокаРаздела(имя: найденный.имя, путь: найденный.путь, ключ: найденный.ключ,
                                  краска: найденный.краска, буква: nil) { раздел(найденный.ключ) }
                case .запрос(let строка):
                    СтрокаЗапроса(строка: строка, выбрать: выбратьЗапрос, сбоку: { вставить(строка.текст) })
                }
            }
        }
    }

    @ViewBuilder
    private var набрано: some View {
        if let запрос = выдача.запрос {
            СтрокаЗапроса(строка: запрос, выбрать: выбратьЗапрос, сбоку: nil)
        }
        if !выдача.разделы.isEmpty {
            Заголовок(текст: т("sov_in_cats"), кнопка: nil, действие: nil)
            ForEach(выдача.разделы, id: \.self) { найденный in
                СтрокаРаздела(имя: найденный.имя, путь: найденный.путь, ключ: найденный.ключ,
                              краска: найденный.краска, буква: nil) { раздел(найденный.ключ) }
            }
        }
        if !выдача.бренды.isEmpty {
            Заголовок(текст: т("sov_brands"), кнопка: nil, действие: nil)
            ForEach(выдача.бренды, id: \.self) { найденный in
                СтрокаРаздела(имя: найденный.имя,
                              путь: String(format: т("sov_in"), найденный.имяРаздела),
                              ключ: найденный.раздел, краска: найденный.краска,
                              буква: String(найденный.имя.prefix(1)).uppercased()) {
                    бренд(найденный.раздел, найденный.имя)
                }
            }
        }
        ForEach(выдача.строки, id: \.self) { строка in
            СтрокаЗапроса(строка: строка, выбрать: выбратьЗапрос, сбоку: { вставить(строка.текст) })
        }
    }
}

/// .mk-sov-sec: 11 pt, 800, заглавными, серым; справа — «Очистить» зелёным.
private struct Заголовок: View {
    let текст: String
    let кнопка: String?
    let действие: (() -> Void)?

    var body: some View {
        HStack {
            Text(текст.uppercased())
                .font(.system(size: 11, weight: .heavy))
                .tracking(0.44)
                .foregroundStyle(Theme.текстВторой)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let кнопка, let действие {
                Button(action: действие) {
                    Text(кнопка)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.зелёный2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 16)
        .padding(.bottom, 6)
    }
}

/// .mk-sov-row: круг 36 pt со значком, текст 16 pt (выделенное — жирным 800), справа 34 pt — «↖» или «×».
private struct СтрокаЗапроса: View {
    let строка: ПодсказкиСайта.Строка
    let выбрать: (String) -> Void
    let сбоку: (() -> Void)?

    private func т(_ ключ: String) -> String { ПоискСайтаText.т(ключ) }

    private var значок: String {
        switch строка.вид {
        case .недавний: return "clock"
        case .запрос, .подсказка: return "magnifyingglass"
        case .тренд: return "chart.line.uptrend.xyaxis"
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Button { выбрать(строка.текст) } label: {
                HStack(spacing: 14) {
                    Image(systemName: значок)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(строка.вид == .тренд ? Theme.зелёныйЯркий : Theme.текстВторой)
                        .frame(width: 36, height: 36)
                        .background(строка.вид == .тренд ? Color(uiColor: Theme.hex(0x16A34A, 0.12)) : Theme.поверхность2,
                                    in: Circle())
                        .accessibilityHidden(true)
                    надпись
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.текст)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let сбоку, строка.вид != .запрос {
                Button(action: сбоку) {
                    Image(systemName: строка.вид == .недавний ? "xmark" : "arrow.up.left")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.текстВторой)
                        .flipsForRightToLeftLayoutDirection(true)
                        .frame(width: 34, height: 34)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(т(строка.вид == .недавний ? "sov_remove" : "sov_insert"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    /// Текст строки: выделенная часть — жирным (<b> сайта).
    private var надпись: Text {
        let текст = строка.текст
        guard let жирно = строка.жирно, жирно.lowerBound >= 0, жирно.upperBound <= текст.count,
              жирно.lowerBound < жирно.upperBound else {
            return Text(текст)
        }
        let до = String(текст.prefix(жирно.lowerBound))
        let середина = String(текст.dropFirst(жирно.lowerBound).prefix(жирно.count))
        let после = String(текст.dropFirst(жирно.upperBound))
        let начало = Text(до)
        let выделено = Text(середина).fontWeight(.heavy)
        let конец = Text(после)
        return начало + выделено + конец
    }
}

/// .mk-sov-catrow: квадрат 40 pt краской раздела на 12 % подложке, имя 15 pt жирным, путь 12 pt серым, «›».
private struct СтрокаРаздела: View {
    let имя: String
    let путь: String
    let ключ: String
    let краска: String
    /// Бренд без логотипа — первая буква (.mk-brand-badge); nil — значок раздела.
    let буква: String?
    let действие: () -> Void

    var body: some View {
        Button(action: действие) {
            HStack(spacing: 12) {
                значок
                    .frame(width: 40, height: 40)
                    .background(Color(uiColor: Theme.hex(краска).withAlphaComponent(0.12)),
                                in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(имя)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.текст)
                        .lineLimit(1)
                    if !путь.isEmpty {
                        Text(путь)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.текстВторой)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(uiColor: Theme.hex(0xC2CCC6)))
                    .flipsForRightToLeftLayoutDirection(true)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var значок: some View {
        if let буква {
            Text(буква)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(Color(uiColor: Theme.hex(краска)))
        } else {
            Image(systemName: РазделыСайта.значок(ключ))
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Color(uiColor: Theme.hex(краска)))
        }
    }
}
