import SwiftUI
import UIKit

/**
 «МОЙ ДОМ» — ТЕХНИКА ПО МОДЕЛИ (docs/STANDARDS.md §3.11 «Расходники по модели», §8.2 «Техника по модели»).

 Карточка — техника строками («Bosch Serie 4 · Стиральная машина · Ванная») и частые виды чипами. Лист — вид, «Снять
 наклейку» (камера по нажатию или фото из галереи → текст наклейки читает Vision на телефоне, НаклейкаТехникиДома →
 чипы «бренд» и «модель», касание ставит; пусто — подставляется само; снимок не хранится и не уходит), бренд чипами
 частых и полем, модель, код расходника (фильтр, мешки, капсулы, картридж — по нему потом подбираются расходники),
 габариты Ш×В×Г по желанию и комната. Купленное на Kliko — строкой «Куплено на Kliko · окт 2026 · цена».
 */
struct КарточкаТехникиДома: View {
    let дом: ДомМоего
    let открыть: (ЛистДомаМоего) -> Void

    init(дом: ДомМоего, открыть: @escaping (ЛистДомаМоего) -> Void) {
        self.дом = дом
        self.открыть = открыть
    }

    private func т(_ ключ: String) -> String { МойДомText.т(ключ) }

    static let частые: [ВидТехникиМоего] = [.холодильник, .стиральная, .пылесос, .фильтр, .кондиционер, .кофемашина,
                                             .посудомойка, .водонагреватель]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ЗаголовокМоего(т("mh_appliances"), значок: "powerplug")
            Text(т("mh_appliances_sub"))
                .font(.footnote)
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(дом.техника) { прибор in
                СтрокаДома(значок: прибор.вид.значок, заголовок: прибор.заголовок, подпись: Self.подпись(прибор, дом)) {
                    открыть(.техника(прибор, новая: false))
                }
            }
            if дом.техника.count < ДомМоего.пределТехники {
                ПотокЧипов(зазор: 8) {
                    ForEach(Self.частые, id: \.self) { вид in
                        ЧипМоего(вид.название, выбран: false, значок: "plus") {
                            ОткликСайта.выбор()
                            открыть(.техника(ТехникаМоего(вид: вид), новая: true))
                        }
                    }
                    ЧипМоего(т("mh_app_other"), выбран: false, значок: "plus") {
                        ОткликСайта.выбор()
                        открыть(.техника(ТехникаМоего(вид: .другая), новая: true))
                    }
                }
            }
        }
        .карточкаМоего()
    }

    /// «Стиральная машина · мешки s-bag · Ванная · Куплено на Kliko · окт 2026».
    static func подпись(_ прибор: ТехникаМоего, _ дом: ДомМоего) -> String {
        var части: [String] = []
        if прибор.заголовок != прибор.вид.название { части.append(прибор.вид.название) }
        let расходник = прибор.расходник.trimmingCharacters(in: .whitespaces)
        if !расходник.isEmpty { части.append(расходник) }
        if let комната = дом.имяКомнаты(прибор.комната) { части.append(комната) }
        if let покупка = прибор.покупка { части.append(покупка.подпись) }
        return части.joined(separator: " · ")
    }
}

// MARK: - Лист техники

struct РедакторТехникиДома: View {
    let новая: Bool
    /// Комнаты на миг открытия листа: лист на хранилище не подписан.
    private let комнаты: [КомнатаМоего]
    @Environment(\.dynamicTypeSize) private var размерТекста
    @State private var прибор: ТехникаМоего
    @State private var части: [Double?]
    @State private var камера = false
    @State private var галерея = false
    @State private var читаем = false
    @State private var неПрочитали = false
    @State private var модели: [String] = []
    @State private var бренды: [String] = []
    @Environment(\.dismiss) private var закрыть

    static let частыеБренды: [String] = ["Samsung", "LG", "Bosch", "Beko", "Haier", "Indesit", "Electrolux", "Artel",
                                         "Xiaomi"]

    init(техника: ТехникаМоего, новая: Bool) {
        self.новая = новая
        комнаты = МоёХранилище.shared.запись.дом.комнаты
        _прибор = State(initialValue: техника)
        var см: [Double?] = [nil, nil, nil]
        if let есть = техника.см, есть.count == 3 { см = есть.map { Double($0) } }
        _части = State(initialValue: см)
    }

    private func т(_ ключ: String) -> String { МойДомText.т(ключ) }

    var body: some View {
        ОболочкаРедактораДома(заголовок: прибор.вид.название, сохранить: { сохранить() },
                              удалить: новая ? nil : { удалить() }) {
            блокВида
            блокНаклейки
            блокМодели
            ПолеТекстаДома(заголовок: т("mh_supply"), подсказка: подсказкаРасходника, текст: $прибор.расходник,
                           предел: 40)
            блокГабаритов
            ВыборКомнатыДома(комнаты: комнаты, комната: $прибор.комната)
            if let покупка = прибор.покупка {
                Label(покупка.подписьСЦеной, systemImage: "bag")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.золото)
            }
            if !новая {
                /* «Продать» (владелец 17.10.2026): вид → раздел, марка, модель, габариты, расходник; комната — нет. */
                МалаяКнопкаАвтоподбора(заголовок: ПродатьМоёText.т("msl_sell"), значок: "tag") { продать() }
                    .accessibilityHint(ПродатьМоёText.т("msl_sell_hint"))
            }
        }
        .выборСнимкаДома(камера: $камера, галерея: $галерея) { источник in прочитать(источник) }
        .animation(ДвижениеСайта.смена, value: модели)
        .animation(ДвижениеСайта.смена, value: читаем)
    }

    private var блокВида: some View {
        VStack(alignment: .leading, spacing: 8) {
            ПодписьБлокаДома(т("mh_app_kind"))
            ПотокЧипов(зазор: 8) {
                ForEach(ВидТехникиМоего.allCases, id: \.self) { вид in
                    ЧипМоего(вид.название, выбран: прибор.вид == вид, значок: вид.значок) {
                        ОткликСайта.выбор()
                        прибор.вид = вид
                    }
                }
            }
        }
    }

    // MARK: Наклейка

    private var блокНаклейки: some View {
        VStack(alignment: .leading, spacing: 8) {
            ПодписьБлокаДома(т("mh_sticker"), пояснение: т("mh_sticker_hint"))
            ПотокЧипов(зазор: 8) {
                if КамераПодачи.есть {
                    МалаяКнопкаАвтоподбора(заголовок: т("mh_sticker_shoot"), значок: "camera.viewfinder") { камера = true }
                }
                МалаяКнопкаАвтоподбора(заголовок: т("mh_sticker_gallery"), значок: "photo.on.rectangle") { галерея = true }
            }
            .disabled(читаем)
            if читаем {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(Theme.акцент)
                    Text(т("mh_sticker_reading"))
                        .font(.footnote)
                        .foregroundStyle(Theme.текстВторой)
                }
                .transition(.opacity)
            }
            if неПрочитали {
                Text(т("mh_sticker_none"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.оранжевый)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
            if !модели.isEmpty || !бренды.isEmpty {
                Text(т("mh_sticker_found"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.текстВторой)
                ПотокЧипов(зазор: 8) {
                    ForEach(бренды, id: \.self) { б in
                        ЧипМоего(б, выбран: прибор.бренд == б, значок: "tag") {
                            ОткликСайта.выбор()
                            прибор.бренд = б
                        }
                    }
                    ForEach(модели, id: \.self) { м in
                        ЧипМоего(м, выбран: прибор.модель == м, значок: "barcode") {
                            ОткликСайта.выбор()
                            прибор.модель = String(м.prefix(60))
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: Бренд и модель

    private var блокМодели: some View {
        VStack(alignment: .leading, spacing: 10) {
            ПолеТекстаДома(заголовок: т("mh_brand"), подсказка: т("mh_brand_ph"), текст: $прибор.бренд, предел: 30)
            ПотокЧипов(зазор: 8) {
                ForEach(Self.частыеБренды, id: \.self) { б in
                    ЧипМоего(б, выбран: прибор.бренд == б) {
                        ОткликСайта.выбор()
                        прибор.бренд = прибор.бренд == б ? "" : б
                    }
                }
            }
            ПолеТекстаДома(заголовок: т("mh_model"), подсказка: т("mh_model_ph"), текст: $прибор.модель, предел: 60)
        }
    }

    private var подсказкаРасходника: String {
        switch прибор.вид {
        case .фильтр, .пылесос, .робот, .кофемашина, .принтер, .кондиционер:
            return т("mh_supply_ph_" + прибор.вид.rawValue)
        default:
            return т("mh_supply_ph")
        }
    }

    // MARK: Габариты

    private var блокГабаритов: some View {
        VStack(alignment: .leading, spacing: 8) {
            ПодписьБлокаДома(т("mh_app_dims"), пояснение: т("mh_app_dims_hint"))
            if размерТекста.isAccessibilitySize {
                VStack(spacing: 10) {
                    поле(0, т("mh_w"))
                    поле(1, т("mh_h"))
                    поле(2, т("mh_d"))
                }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    поле(0, т("mh_w"))
                    поле(1, т("mh_h"))
                    поле(2, т("mh_d"))
                }
            }
        }
    }

    private func поле(_ номер: Int, _ заголовок: String) -> some View {
        ПолеЧислаМоего(заголовок: заголовок, единица: т("mh_cm"), значение: Binding(get: { части[номер] }, set: { новое in
            части[номер] = новое
            применитьЧасти()
        }), пределы: 1...500, знаков: 0)
    }

    /// Все три числа — габариты есть; стёрли одно — габаритов нет.
    private func применитьЧасти() {
        let числа = части.compactMap { $0 }.map { Int($0.rounded()) }
        прибор.см = числа.count == 3 && числа.allSatisfy({ $0 > 0 && $0 <= 500 }) ? числа : nil
    }

    // MARK: Чтение наклейки

    private func прочитать(_ источник: ИсточникСнимкаМоего) {
        читаем = true
        неПрочитали = false
        Task { @MainActor in
            let строки = await Task.detached(priority: .userInitiated) { НаклейкаТехникиДома.строки(источник) }.value
            let найдено = НаклейкаТехникиДома.разобрать(строки)
            читаем = false
            модели = найдено.модели
            бренды = найдено.бренды
            неПрочитали = найдено.модели.isEmpty && найдено.бренды.isEmpty
            guard !неПрочитали else {
                ОткликСайта.предупреждение()
                UIAccessibility.post(notification: .announcement, argument: т("mh_sticker_none"))
                return
            }
            // Пустые поля — сразу первым найденным; заполненные — только чипами.
            if прибор.модель.trimmingCharacters(in: .whitespaces).isEmpty, let первая = найдено.модели.first {
                прибор.модель = String(первая.prefix(60))
            }
            if прибор.бренд.trimmingCharacters(in: .whitespaces).isEmpty, let первый = найдено.бренды.first {
                прибор.бренд = первый
            }
            ОткликСайта.успех()
            UIAccessibility.post(notification: .announcement,
                                 argument: т("mh_sticker_found") + ": " + (найдено.бренды + найдено.модели).joined(separator: ", "))
        }
    }

    // MARK: Запись

    private func сохранить() {
        let готовый = прибор
        МоёХранилище.shared.обновитьДом { д in
            if let i = д.техника.firstIndex(where: { $0.id == готовый.id }) {
                д.техника[i] = готовый
            } else if д.техника.count < ДомМоего.пределТехники {
                д.техника.append(готовый)
            }
        }
    }

    private func удалить() {
        let id = прибор.id
        МоёХранилище.shared.обновитьДом { д in д.техника.removeAll { $0.id == id } }
    }

    /// Лист закрывается, мастер подачи открывается заполненным (то, что сейчас на листе).
    private func продать() {
        let заготовка: ЗаготовкаПодачи = ПродатьСвоёМоего.техника(прибор)
        ОткликСайта.выбор()
        закрыть()
        ПереходыГардероба.продать(заготовка)
    }
}
