import Foundation
import SwiftUI
import UIKit

/**
 ПОДАЧА И ПРАВКА ОБЪЯВЛЕНИЯ — СОСТОЯНИЕ И ПРАВИЛА САЙТА, ЭТАП 42 (владелец 26.09.2026: «всё одно и то же, просто код
 разный»; Config.нативнаяПодача).

 Мастер сайта ?go=add и правка ?edit=<id> (карта кабинета §2, §8.4): стартовый экран «Что размещаете?», семь шагов
 ADD_STEPS (Фото → Данные товара → Характеристики → Цена и состояние → Адрес → Дополнительно → Проверка), шаг без
 видимых блоков пропускается, «Далее» проверяет то же и теми же словами (addStepNext), отправка — те же проверки, что
 у настоящего doSubmit из модуля compose (js/cabinet-compose.min.js: название, описание от 10 символов, цена или «Торг»,
 город — окно «Не хватает города», режим работы услуги), потом окно «Проверьте перед публикацией» с вопросом «Вещь
 работает?» и гарантом, потом submit. Правка — проверки _doEditSaveReal и edit_item.

 Правила разделов — как у сайта: updateCondUI (подписи состояния), updateDataLabels (бренд — только у товаров),
 specsFor (E_SPECS вверх по дереву), vinAllowed, isRentableCategory (NO_RENT_ROOTS), обмен (не у животных), часы
 (обязательны у услуг), catAsksWorks, escrowLockWhy, photoCap (5; 10 у недвижимости и транспорта; 30 с ТОПом).

 🔴 ОШИБКИ САЙТА НЕ ПЕРЕНОСИМ (§8.0.6): в «Этого уже ждут» (subs.php?action=reach) сайт шлёт цену из поля с пробелами,
 и parseInt превращает «150 000» в 150 — здесь уходит полное целое. Остальные тела — байт в байт.

 ТОП при подаче сайт списывает с кошелька (top_preset) — в приложении его нет, top_preset всегда пустой. Слоты
 и продвижение после публикации — только через App Store (ЛистУслугиApple) при Config.цифровыеПокупки; выключено —
 одни сведения. Ссылок на оплату на сайте нет.

 Черновик — как ulx_draft_add сайта: на телефоне, 7 дней, «Есть незаконченное объявление» при следующем открытии;
 стирается при выходе (ВыходНачисто) и после удачной подачи. Правка черновика не пишет.
 */

/// Что открыть: новое объявление или правку по номеру.
enum ЦельПодачи: Identifiable, Equatable, Hashable {
    case новое
    case правка(String)

    var id: String {
        switch self {
        case .новое: return "new"
        case .правка(let номер): return "edit:" + номер
        }
    }
}

/// Кто показывает мастер: вкладки (NativeTabsView) держат поверх себя fullScreenCover на эту цель.
@MainActor
final class ПодачаОкно: ObservableObject {
    static let shared = ПодачаОкно()

    @Published var цель: ЦельПодачи? = nil

    private init() {}

    /// Мастер включён рубильником и нативный слой на месте — открыть; иначе false: пусть откроет страница сайта.
    @discardableResult
    func открыть(_ новая: ЦельПодачи) -> Bool {
        guard Config.нативнаяПодача else { return false }
        цель = новая
        return true
    }
}

/// ADD_STEPS сайта: k и заголовок.
enum ШагПодачи: Int, CaseIterable, Identifiable {
    case фото, данные, характеристики, цена, адрес, дополнительно, проверка

    var id: Int { rawValue }

    var ключ: String {
        switch self {
        case .фото: return "photo"
        case .данные: return "what"
        case .характеристики: return "specs"
        case .цена: return "price"
        case .адрес: return "where"
        case .дополнительно: return "extra"
        case .проверка: return "check"
        }
    }

    var название: String { ПодачаText.т("step_" + ключ) }
}

/// ТОП, подключённый при подаче (PUBLISH_TOP сайта): ключ пакета, подпись, цена.
struct ТопПодачи: Codable, Equatable {
    var ключ: String
    var подпись: String
    var цена: Int
}

/**
 Поля формы. Имена — по-русски, смысл — поля сайта (f-*): что уходит в submit, сказано у каждого. Codable — это
 и черновик (ulx_draft_add сайта хранит те же значения полей).
 */
struct ФормаПодачи: Codable, Equatable {
    /// ADD_TYPE: goods · services · rentgood · realty · "" (транспорт) — уходит в recognize как atype.
    var тип: String = ""
    /// ADD_ENTRY.t — подпись плитки стартового экрана (recognize.entry).
    var плитка: String = ""
    /// Подзаголовок той же плитки («смартфон, планшет») — строка под типом на полосе #aft-bar.
    var плиткаПодпись: String? = nil
    /// window._addHint — подсказка Kliko AI («Это смартфон/мобильный телефон»).
    var подсказка: String = ""
    /// Не длиннее ПределыПодачи.название (75): обрезается при любой записи — ввод, Kliko AI, правка.
    var название: String = "" {
        didSet { if название.count > ПределыПодачи.название { название = ПределыПодачи.обрезать(название, ПределыПодачи.название) } }
    }
    /// Короткие поля — не длиннее ПределыПодачи.короткое (30).
    var бренд: String = "" {
        didSet { if бренд.count > ПределыПодачи.короткое { бренд = ПределыПодачи.обрезать(бренд, ПределыПодачи.короткое) } }
    }
    /// f-model / f-gen — мастер авто.
    var модель: String = "" {
        didSet { if модель.count > ПределыПодачи.короткое { модель = ПределыПодачи.обрезать(модель, ПределыПодачи.короткое) } }
    }
    var поколение: String = "" {
        didSet { if поколение.count > ПределыПодачи.короткое { поколение = ПределыПодачи.обрезать(поколение, ПределыПодачи.короткое) } }
    }
    var раздел: String = ""
    var описание: String = ""
    var cpu: String = "" {
        didSet { if cpu.count > ПределыПодачи.короткое { cpu = ПределыПодачи.обрезать(cpu, ПределыПодачи.короткое) } }
    }
    var gpu: String = "" {
        didSet { if gpu.count > ПределыПодачи.короткое { gpu = ПределыПодачи.обрезать(gpu, ПределыПодачи.короткое) } }
    }
    var ram: String = "" {
        didSet { if ram.count > ПределыПодачи.короткое { ram = ПределыПодачи.обрезать(ram, ПределыПодачи.короткое) } }
    }
    var storage: String = "" {
        didSet { if storage.count > ПределыПодачи.короткое { storage = ПределыПодачи.обрезать(storage, ПределыПодачи.короткое) } }
    }
    /// «Год выпуска» — выбирается из списка (ПределыПодачи.годы); старое значение правки остаётся как есть.
    var year: String = "" {
        didSet { if year.count > ПределыПодачи.короткое { year = ПределыПодачи.обрезать(year, ПределыПодачи.короткое) } }
    }
    var vin: String = ""
    /// used | new
    var состояние: String = "used"
    /// «Вещь работает?»: "" — не ответил, ok, bad.
    var работает: String = ""
    /// Только цифры (priceNum сайта).
    var цена: String = ""
    var торг: Bool = false
    var аренда: Bool = false
    /// day | month
    var период: String = "day"
    var ставка: String = ""
    var залог: String = ""
    var минСрок: String = "1"
    var комплект: String = ""
    var тожеПродаю: Bool = false
    var обмен: Bool = false
    var склад: String = ""
    /// f-escrow: гарант включён (escrow_off = !гарант).
    var гарант: Bool = true
    var регион: String = ""
    var район: String = ""
    var город: String = ""
    var адрес: String = ""
    var lat: String = ""
    var lon: String = ""
    /// hours_mode: "" (в любое время) · 247 · range.
    var часы: String = ""
    var часыС: String = ""
    var часыДо: String = ""
    /// Выбран ли пресет часов пользователем (у услуг режим обязателен — пустой не годится).
    var часыВыбраны: Bool = false
    /// REALTY_DATA: deal (sale | rent), kind и значения полей REALTY_FIELDS (переключатели — отдельно).
    var сделка: String = ""
    var вид: String = ""
    var недвижимость: [String: String] = [:]
    var флагиНедвижимости: [String: Bool] = [:]
    /// PARTS_DATA: значения полей PARTS_FIELDS (kind — по разделу, _pwKindFor).
    var запчасть: [String: String] = [:]
    /// «Дополнительно» (_formCfg сайта) — уходит после подачи отдельными запросами.
    var рассрочка: Bool = false
    var кредит: Bool = false
    var доставкаЗадана: Bool = false
    var доставкаБесплатно: Bool = false
    var доставкаДней: String = ""
    var доверияЗадано: Bool = false
    var гарантияДней: Int = 0
    var знаки: [String] = []
    var топ: ТопПодачи? = nil
    /// Урлы загруженных фото по порядку — только для черновика (плитки живут в модели).
    var фото: [String] = []

    /// Черновик читается декодером мимо didSet — обрезаем длины сами.
    mutating func обрезатьДлины() {
        название = ПределыПодачи.обрезать(название, ПределыПодачи.название)
        бренд = ПределыПодачи.обрезать(бренд, ПределыПодачи.короткое)
        модель = ПределыПодачи.обрезать(модель, ПределыПодачи.короткое)
        поколение = ПределыПодачи.обрезать(поколение, ПределыПодачи.короткое)
        cpu = ПределыПодачи.обрезать(cpu, ПределыПодачи.короткое)
        gpu = ПределыПодачи.обрезать(gpu, ПределыПодачи.короткое)
        ram = ПределыПодачи.обрезать(ram, ПределыПодачи.короткое)
        storage = ПределыПодачи.обрезать(storage, ПределыПодачи.короткое)
        year = ПределыПодачи.обрезать(year, ПределыПодачи.короткое)
    }
}

/**
 Пределы длины полей подачи (владелец 26.09.2026): название — 75 знаков, бренд и короткие поля (своё значение
 характеристики, модель и поколение авто, cpu/gpu/ram/storage, текстовые поля недвижимости и запчастей) — 30.
 Описание, адрес, цены и числа, VIN и «Комплект» — со своими правилами. «Год выпуска» — выбор из списка лет.
 */
enum ПределыПодачи {
    static let название = 75
    static let короткое = 30
    /// За сколько знаков до предела показать счётчик у короткого поля (от 25 из 30).
    static let счётчикЗаранее = 5
    /// Самый старый год в списке «Год выпуска».
    static let первыйГод = 2000

    static func обрезать(_ текст: String, _ предел: Int) -> String {
        guard предел > 0, текст.count > предел else { return текст }
        return String(текст.prefix(предел))
    }

    /// Годы от текущего (по календарю телефона) до 2000, новые сверху.
    static var годы: [String] {
        let сейчас = max(Calendar.current.component(.year, from: Date()), первыйГод)
        return (первыйГод...сейчас).reversed().map { String($0) }
    }
}

/// Плитка фото: превью, загрузка, ошибка с «повторить».
struct ПлиткаФото: Identifiable, Equatable {
    let id: UUID
    var url: String
    var превью: UIImage?
    var картинка: Data?
    var миниатюра: Data?
    var грузится: Bool
    var ошибка: String?

    /// Ход загрузки для кольца на плитке: 0 — сжимаем и ставим знак, 1 — отправляем на сервер.
    var этап: Int = 0

    var готова: Bool { !url.isEmpty }
}

/// Вопрос с двумя кнопками — окна boostConfirm / showConfirm сайта.
struct ВопросПодачи: Identifiable {
    let id = UUID()
    let заголовок: String
    let текст: String
    let да: String
    let нет: String
    let действие: () -> Void
    let отказ: (() -> Void)?
    /// Третья кнопка (heldChoice сайта: «Расширить лимит» · «Пройти верификацию (+5)» · «Позже»).
    let ещё: String?
    let ещёДействие: (() -> Void)?

    init(заголовок: String, текст: String, да: String, нет: String, действие: @escaping () -> Void,
         отказ: (() -> Void)? = nil, ещё: String? = nil, ещёДействие: (() -> Void)? = nil) {
        self.заголовок = заголовок
        self.текст = текст
        self.да = да
        self.нет = нет
        self.действие = действие
        self.отказ = отказ
        self.ещё = ещё
        self.ещёДействие = ещёДействие
    }
}

/// Окно с одной кнопкой «Понятно» — showProhibitedWarning и обязательные ответы сайта.
struct СообщениеПодачи: Identifiable {
    let id = UUID()
    let заголовок: String
    let текст: String

    init(заголовок: String, текст: String) {
        self.заголовок = заголовок
        self.текст = текст
    }
}

/// Окно итога подачи (§2.5.2) — что сайт показывает по ответу submit.
enum ИтогПодачи: Equatable {
    case опубликовано(id: String)
    /// id — номер сохранённого объявления (экран после подачи: «Продвинуть», «Поделиться»).
    case наПроверке(id: String)
    case отклонено(String)
    case сохраненоИИ(часы: String)
    case ждётВерификации(String)
    case неактивные(текст: String, верификация: Bool)
    case лимит(String)
    case запрещено(заголовок: String, текст: String)
}

/// Подсказка цены: «Рынок · N» из price_stats или «Kliko AI-оценка» из recognize — три якоря «Срочно / Рынок / Высокая».
struct ПодсказкаЦены: Equatable {
    let подпись: String
    let низ: Int
    let середина: Int
    let верх: Int
}

@MainActor
final class ПодачаМодель: ObservableObject {
    enum Экран: Equatable {
        case загрузка
        case нуженВход
        case ошибка(String)
        case старт
        case шаги
    }

    /// Экраны стартового окна (_asNav сайта): root, goods, clothing, animals, rentgood, realty (сделка, вид), auto.
    enum Старт: Equatable {
        case корень
        case товар
        case одежда
        case животные
        case аренда
        case сделка
        case видНедвижимости(String)
        case транспорт
    }

    enum Режим: Equatable {
        case товар, недвижимость, авто, запчасти, услуга, работа
    }

    let цель: ЦельПодачи

    @Published var экран: Экран = .загрузка
    @Published var старт: Старт = .корень
    @Published var шаг: ШагПодачи = .фото
    @Published var форма = ФормаПодачи() {
        didSet { формаИзменилась(было: oldValue) }
    }
    @Published var плитки: [ПлиткаФото] = [] {
        didSet { запланироватьЧерновик() }
    }
    @Published var справочники = СправочникиПодачи()
    @Published var страница = СтраницаПодачи()
    @Published var плашка: String? = nil
    @Published var вопрос: ВопросПодачи? = nil
    @Published var итог: ИтогПодачи? = nil
    /// «Проверьте перед публикацией» (showPublishConfirm из модуля compose).
    @Published var подтверждение = false
    @Published var отправляем = false
    @Published var распознаём = false
    @Published var шагРаспознавания = 0
    /// Номер запуска «Распознать»: «Заполнить вручную» его сдвигает — поздний ответ старого запуска форму не трогает.
    var номерРаспознавания = 0
    /// Строка под фото (setAiStatus сайта): итог Kliko AI или ошибка.
    @Published var статусИИ: String? = nil
    /// Бейдж «✓ Kliko AI» у названия.
    @Published var заполненоИИ = false
    @Published var подсказкаЦены: ПодсказкаЦены? = nil
    /// Текст price_stats под ценой и его тон (0 — в рынке/зелёный, 1 — дороже/жёлтый).
    @Published var рынок: String? = nil
    @Published var рынокДорого = false
    /// «Этого уже ждут: {n}».
    @Published var ждут = 0
    @Published var маркиАвто: [String] = []
    @Published var моделиАвто: [МодельАвто] = []
    /// Марки группами, как их отдаёт /api/auto_models.php?brands=1 (region) — сетка мастера авто.
    @Published var группыМарок: [ГруппаМарок] = []
    /// Справочник марок не ответил — в мастере только «Другая марка — вписать».
    @Published var маркиНеДоступны = false
    /// Модели по марке — как _AW_MODELS сайта: второй раз не спрашиваем.
    var кэшМоделейАвто: [String: [МодельАвто]] = [:]
    /// Мастер поверх шагов (autoWizOpen / realtyWizOpen сайта): сначала марка и модель, потом фото.
    @Published var мастер: МастерПодачи? = nil
    /// Мастер недвижимости уже показывали в этой подаче — на «Далее» с «Фото» сам второй раз не открывается.
    var мастерНедвижимостиБыл = false
    /// Мастер услуги (#svc-wizard-panel сайта): направление и ответы — живут, пока идёт подача.
    @Published var услуга = ЗаготовкаУслуги() {
        didSet { if услуга != oldValue { запланироватьЧерновик() } }
    }
    @Published var собираемУслугу = false
    /// Плитка постера-обложки, пока она грузится (урла ещё нет); после загрузки — по услуга.обложка.
    var обложкаПлитка: UUID? = nil
    @Published var типыЗапчастей: [ВариантПоля] = []
    @Published var сообщение: СообщениеПодачи? = nil
    /// Страница сайта, которую надо открыть (деньги, верификация, «Работа»): экран закрывает мастер и открывает её.
    @Published var открытьСтраницу: String? = nil
    /// Сервер ответил «auth» посреди мастера — лист входа поверх формы, форма остаётся.
    @Published var войти = false
    /// Плашки сайта после подачи («ТОП подключён…») — покажет «Мои объявления», куда ведёт итог.
    var плашкаПосле = ""
    /// ТОП подключён при подаче (top_applied) — экран после подачи говорит «ТОП уже подключён».
    var топПослеПодачи = false
    /// Проверки шагов — строкой под своим полем, а не окном: ключ поля (title, category, desc, price, hours, city,
    /// works, auto) → текст сайта. Исправил поле — строка уходит сама (снятьОшибки).
    @Published var ошибкиПолей: [String: String] = [:]
    /// Правка: форма и фото, как пришли из my_items, — по ним шаги с изменениями помечаются точкой.
    var исходнаяФорма: ФормаПодачи? = nil
    var исходныеФото: [String] = []

    /// Правка: запись my_items как есть — всё, чего мастер не показывает (опт, вариации, раздел магазина, скрытие
    /// номеров, метки кадров), уходит в edit_item тем же, что было: иначе сохранение стёрло бы это.
    var исходник: [String: Any] = [:]
    /// Правка: у объявления активный ТОП — до 30 фото (window._editTopActive).
    var топВПравке = false

    private var черновикЗадача: Task<Void, Never>? = nil
    private var ценаЗадача: Task<Void, Never>? = nil
    private var последнийРынок = ""
    private var последнийОхват = ""
    private var автоНазвание = ""
    private var автоОписание = ""
    /// Пока форма заполняется из черновика или записи — черновик не пишем и производные не трогаем.
    var заполняем = false

    static let ключЧерновика = "kliko_add_draft"
    /// 7 дней — срок черновика сайта (6048e5 мс).
    static let срокЧерновика: TimeInterval = 7 * 24 * 3600

    init(цель: ЦельПодачи) {
        self.цель = цель
    }

    func т(_ ключ: String) -> String { ПодачаText.т(ключ) }

    var правка: Bool {
        if case .правка = цель { return true }
        return false
    }

    var номерПравки: String {
        if case .правка(let номер) = цель { return номер }
        return ""
    }

    // MARK: - Правила разделов

    var корень: String {
        guard !форма.раздел.isEmpty else { return "" }
        return справочники.корень(форма.раздел)
    }

    var режим: Режим {
        switch корень {
        case "services": return .услуга
        case "jobs": return .работа
        case "realty": return .недвижимость
        case "transport":
            return справочники.внутри(форма.раздел, ["auto-parts"]) ? .запчасти : .авто
        case "":
            return форма.тип == "realty" ? .недвижимость : .товар
        default:
            return .товар
        }
    }

    var услугаИлиРабота: Bool { режим == .услуга || режим == .работа }

    /// updateDataLabels: бренд виден только у товаров; у авто и запчастей его задаёт мастер.
    var брендВиден: Bool { режим == .товар && !форма.раздел.isEmpty }

    var бренды: [String] {
        guard брендВиден else { return [] }
        return справочники.вверх(форма.раздел, справочники.бренды) ?? []
    }

    /// specsFor: у услуг и работы характеристик нет; у недвижимости, авто и запчастей — свои мастера.
    var характеристики: [ПолеХарактеристики] {
        guard режим == .товар, !форма.раздел.isEmpty else { return [] }
        return справочники.вверх(форма.раздел, справочники.характеристики) ?? []
    }

    var vinРазрешён: Bool {
        guard корень == "transport" else { return false }
        return !справочники.внутри(форма.раздел, ["e-scooters", "auto-parts", "water-transport"])
    }

    /// _pwKindFor: вид запчасти по разделу.
    var видЗапчасти: String {
        switch форма.раздел {
        case "tires-wheels": return "tire"
        case "auto-oils": return "oil"
        case "auto-lighting": return "light"
        case "auto-accessories": return "accessory"
        case "auto-audio": return "audio"
        default: return "part"
        }
    }

    var поляЗапчасти: [ПолеМастера] { справочники.запчасти[видЗапчасти] ?? [] }

    var поляНедвижимости: [ПолеМастера] {
        guard !форма.сделка.isEmpty, !форма.вид.isEmpty else { return [] }
        return справочники.недвижимость[форма.сделка]?[форма.вид] ?? []
    }

    /// isRentableCategory: корни кроме food-farm, beauty, services, jobs, animals; у «Сдать вещь» — всегда.
    var арендаДоступна: Bool {
        if форма.тип == "rentgood" { return true }
        guard !форма.раздел.isEmpty else { return false }
        return !["food-farm", "beauty", "services", "jobs", "animals"].contains(корень)
    }

    var обменВиден: Bool { корень != "animals" && !форма.раздел.isEmpty }

    /// updateCondUI: у услуг и работы блока нет, у сдаваемой недвижимости тоже.
    var состояниеВидно: Bool {
        if услугаИлиРабота { return false }
        if режим == .недвижимость && форма.аренда { return false }
        return true
    }

    var подписиСостояния: (б: String, н: String) {
        switch режим {
        case .недвижимость: return (т("cond_resale"), т("cond_newbuild"))
        case .авто: return (т("cond_mileage"), т("cond_no_mileage"))
        default: return (т("cond_used"), т("cond_new"))
        }
    }

    /// catAsksWorks + б/у: «Вещь работает?» (worksNeeded).
    var нужнаИсправность: Bool {
        guard состояниеВидно, форма.состояние == "used", !форма.раздел.isEmpty else { return false }
        var текущий: String? = форма.раздел
        var шаги = 0
        while let узел = текущий, шаги < 25 {
            if страница.работаетКроме.contains(узел) { return false }
            if страница.работаетВ.contains(узел) { return true }
            текущий = справочники.разделы[узел]?.родитель
            шаги += 1
        }
        return false
    }

    var ценаЧислом: Int { Int(Self.цифры(форма.цена)) ?? 0 }
    var ставкаЧислом: Int { Int(Self.цифры(форма.ставка)) ?? 0 }
    var залогЧислом: Int { Int(Self.цифры(форма.залог)) ?? 0 }

    /**
     Только цифры 0–9 латиницей, не больше предела (priceNum сайта). Цифровая клавиатура на арабском телефоне даёт
     «٣٤٥» — Int их не читает, поэтому каждая цифра переводится в латинскую по её значению.
     */
    nonisolated static func цифры(_ текст: String, предел: Int = 12) -> String {
        var итог = ""
        for символ in текст {
            guard let значение = символ.wholeNumberValue, значение >= 0, значение <= 9 else { continue }
            итог.append(String(значение))
            if итог.count >= предел { break }
        }
        return итог
    }

    /// Число с дробью («1.6», «54,5»): цифры по значению, разделитель — как ввёл человек (арабская «٫» → «.»).
    nonisolated static func дробное(_ текст: String, предел: Int = 12) -> String {
        var итог = ""
        for символ in текст {
            if let значение = символ.wholeNumberValue, значение >= 0, значение <= 9 {
                итог.append(String(значение))
            } else if символ == "." || символ == "," {
                итог.append(символ)
            } else if символ == "٫" {
                итог.append(".")
            }
            if итог.count >= предел { break }
        }
        return итог
    }

    /// escrowLockWhy: hide · parts · broken · min · "" (гарант можно).
    var запретГаранта: String {
        if режим == .работа { return "hide" }
        if форма.аренда && !форма.тожеПродаю && ценаЧислом <= 0 { return "hide" }
        if режим == .запчасти { return "parts" }
        if нужнаИсправность && форма.работает == "bad" { return "broken" }
        let минимум = страница.минимумГаранта
        if минимум > 0 && режим != .услуга && ценаЧислом > 0 && ценаЧислом < минимум { return "min" }
        return ""
    }

    /// photoCap: 30 с ТОПом, 10 у недвижимости и транспорта, иначе 5.
    var лимитФото: Int {
        if правка && топВПравке { return 30 }
        if !правка && форма.топ != nil { return 30 }
        var к = корень
        if к.isEmpty { к = форма.тип == "realty" ? "realty" : "" }
        return (к == "realty" || к == "transport") ? 10 : 5
    }

    var готовыеФото: [String] { плитки.filter { $0.готова }.map { $0.url } }
    var фотоГрузятся: Bool { плитки.contains { $0.грузится } }

    /// renderCfgRows: строки «Дополнительно» по корню раздела.
    var строкиДополнительно: [String] {
        guard !форма.раздел.isEmpty else { return [] }
        let к = корень
        var строки: [String] = []
        if !["animals", "services", "jobs"].contains(к) { строки.append("pay") }
        if !["services", "jobs", "realty", "transport"].contains(к) { строки.append("del") }
        if к != "jobs" { строки.append("trust") }
        return строки
    }

    /// trustAttrsFor: группа TRUST_SETS по корню, у сдаваемого — плюс TRUST_RENT (его страница не печатает — без него).
    var знакиДоверия: [ЗнакДоверия] {
        let группы: [String: String] = ["transport": "transport", "realty": "realty", "animals": "animals",
                                       "clothing": "clothing", "kids": "kids", "services": "services",
                                       "jobs": "services"]
        let группа = группы[корень] ?? "goods"
        return страница.знаки[группа] ?? страница.знаки["goods"] ?? []
    }

    // MARK: - Шаги

    /// _addStepHas: шаг без видимых блоков пропускается.
    func виден(_ ш: ШагПодачи) -> Bool {
        switch ш {
        case .характеристики:
            return !характеристики.isEmpty || режим == .недвижимость || режим == .авто || режим == .запчасти || vinРазрешён
                || брендВиден
        case .дополнительно:
            return !строкиДополнительно.isEmpty
        default:
            return true
        }
    }

    var видимыеШаги: [ШагПодачи] { ШагПодачи.allCases.filter { виден($0) } }

    /// Название шага в полосе: у услуги первый шаг — мастер услуги (фото там необязательно), а не «Фото».
    func названиеШага(_ ш: ШагПодачи) -> String {
        if ш == .фото && режим == .услуга && !правка { return МастерПодачиText.т("svc_step") }
        return ш.название
    }

    /**
     addStepNext: проверки «Данные» и «Цена», потом следующий видимый шаг. С «Фото» авто без марки не уходит — сначала
     мастер «Марка → Модель» (владелец: «при подаче авто сначала бренд и модель, затем фото»); недвижимость без
     параметров — один раз мастер объекта (название и описание собираются из него).
     */
    func далее() {
        if шаг == .фото && !правка {
            if режим == .авто && форма.бренд.trimmingCharacters(in: .whitespaces).isEmpty {
                мастер = .авто(кузов: false)
                return
            }
            if режим == .недвижимость && !мастерНедвижимостиБыл
                && форма.название.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                мастерНедвижимостиБыл = true
                мастер = .недвижимость(сШага: форма.сделка.isEmpty || форма.вид.isEmpty ? 0 : 1)
                return
            }
        }
        switch шаг {
        case .данные:
            if let ошибка = ошибкаДанныхПоля() {
                пометить(ошибка.поле, ошибка.текст)
                return
            }
        case .цена:
            if let ошибка = ошибкаЦены() {
                пометить("price", ошибка)
                return
            }
        default:
            break
        }
        перейти(направление: 1)
    }

    func назад() {
        перейти(направление: -1)
    }

    func перейти(к новый: ШагПодачи) {
        шаг = новый
    }

    private func перейти(направление: Int) {
        var номер = шаг.rawValue + направление
        while let ш = ШагПодачи(rawValue: номер) {
            if виден(ш) {
                шаг = ш
                if ш == .проверка { узнатьОхват() }
                return
            }
            номер += направление
        }
    }

    func ошибкаДанных() -> String? {
        ошибкаДанныхПоля()?.текст
    }

    /// Та же проверка addStepNext, с ключом поля — строка встаёт под ним.
    func ошибкаДанныхПоля() -> (поле: String, текст: String)? {
        if форма.название.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && режим != .авто {
            return ("title", т("need_title"))
        }
        if форма.раздел.isEmpty { return ("category", т("need_cat")) }
        if форма.описание.trimmingCharacters(in: .whitespacesAndNewlines).count < 10 { return ("desc", т("need_desc")) }
        return nil
    }

    func ошибкаЦены() -> String? {
        if услугаИлиРабота || форма.торг || ценаЧислом > 0 || (форма.аренда && ставкаЧислом > 0) { return nil }
        return форма.аренда ? т("need_rent") : т("need_price")
    }

    /// hoursValidate: у услуг режим работы обязателен, у «Своего графика» — оба времени.
    func ошибкаЧасов() -> String? {
        guard услугаИлиРабота else { return nil }
        if форма.часы.isEmpty { return т("hours_req_err") }
        if форма.часы == "range" && (форма.часыС.isEmpty || форма.часыДо.isEmpty) { return т("hours_req_err") }
        return nil
    }

    // MARK: - Раздел

    /// catCascadeSet + catApply: новый раздел перестраивает форму — как у сайта, лишнее для раздела сбрасывается.
    func выбратьРаздел(_ ключ: String) {
        var ф = форма
        ф.раздел = ключ
        let новыйКорень = ключ.isEmpty ? "" : справочники.корень(ключ)
        if ["food-farm", "beauty", "services", "jobs", "animals"].contains(новыйКорень) && ф.тип != "rentgood" {
            ф.аренда = false
        }
        if новыйКорень == "animals" { ф.обмен = false }
        if новыйКорень != "realty" {
            ф.сделка = ""
            ф.вид = ""
            ф.недвижимость = [:]
            ф.флагиНедвижимости = [:]
        } else if ф.вид.isEmpty {
            ф.вид = видНедвижимости(ключ)
            if ф.сделка.isEmpty { ф.сделка = ф.аренда ? "rent" : "sale" }
        }
        if новыйКорень != "transport" { ф.vin = "" }
        форма = ф
        if новыйКорень == "realty" && ф.недвижимость["owner"] == nil { форма.недвижимость["owner"] = "owner" }
    }

    /// Вид недвижимости по разделу (обратное к _ASTART_REALTY: apartments → apartment…).
    func видНедвижимости(_ ключ: String) -> String {
        if справочники.внутри(ключ, ["apartments"]) { return "apartment" }
        if справочники.внутри(ключ, ["houses"]) { return "house" }
        if справочники.внутри(ключ, ["land"]) { return "land" }
        if справочники.внутри(ключ, ["commercial-realty"]) { return "commercial" }
        return "apartment"
    }

    // MARK: - Производные поля (мастер авто и недвижимости)

    private func формаИзменилась(было: ФормаПодачи) {
        if !ошибкиПолей.isEmpty { снятьОшибки(было: было) }
        guard !заполняем else { return }
        if режим == .авто {
            // Обрезаем заранее: иначе didSet укоротит, сравнение не сойдётся и запись пойдёт по кругу.
            let название = ПределыПодачи.обрезать(составитьНазваниеАвто(), ПределыПодачи.название)
            if !название.isEmpty && форма.название != название {
                форма.название = название
                return
            }
        }
        if режим == .недвижимость && (форма.недвижимость != было.недвижимость || форма.вид != было.вид
                                        || форма.сделка != было.сделка) {
            автозаполнитьНедвижимость()
        }
        if было.сделка != форма.сделка && режим == .недвижимость {
            let сдаю = форма.сделка == "rent"
            if форма.аренда != сдаю { форма.аренда = сдаю }
        }
        if режим == .недвижимость && форма.аренда {
            let период = форма.недвижимость["term"] == "daily" ? "day" : "month"
            if форма.период != период { форма.период = период }
        }
        if форма.цена != было.цена || форма.раздел != было.раздел || форма.город != было.город {
            запланироватьРынок()
        }
        запланироватьЧерновик()
    }

    /// autoTitleCompose: «Марка Модель, год, объём л».
    func составитьНазваниеАвто() -> String {
        let марка = форма.бренд.trimmingCharacters(in: .whitespaces)
        guard !марка.isEmpty else { return "" }
        let модель = форма.модель.trimmingCharacters(in: .whitespaces)
        let основа: String
        if !модель.isEmpty && модель.lowercased().hasPrefix(марка.lowercased() + " ") {
            основа = модель
        } else {
            основа = [марка, модель].filter { !$0.isEmpty }.joined(separator: " ")
        }
        var хвост: [String] = []
        if !форма.year.isEmpty { хвост.append(форма.year) }
        if !форма.storage.isEmpty { хвост.append(форма.storage.replacingOccurrences(of: ",", with: ".") + " л") }
        return хвост.isEmpty ? основа : основа + ", " + хвост.joined(separator: ", ")
    }

    /// realtyAutofill: название и описание из параметров, пока человек их не менял (_rwAutoTitleFor, _rwAutoDescFor).
    private func автозаполнитьНедвижимость() {
        let название = ПределыПодачи.обрезать(названиеНедвижимости(), ПределыПодачи.название)
        let сейчас = форма.название.trimmingCharacters(in: .whitespacesAndNewlines)
        if !название.isEmpty && (сейчас.isEmpty || форма.название == автоНазвание) && форма.название != название {
            автоНазвание = название
            форма.название = название
        }
        let описание = описаниеНедвижимости()
        let текущее = форма.описание.trimmingCharacters(in: .whitespacesAndNewlines)
        if !описание.isEmpty && (текущее.isEmpty || форма.описание == автоОписание) && форма.описание != описание {
            автоОписание = описание
            форма.описание = описание
        }
    }

    func названиеНедвижимости() -> String {
        let з = форма.недвижимость
        let площадь = з["area"] ?? ""
        let участок = з["land_area"] ?? ""
        let этаж = з["floor"] ?? ""
        let этажей = з["floors"] ?? ""
        switch форма.вид {
        case "apartment":
            let комнаты = з["rooms"] ?? ""
            var итог = комнаты == "studio" ? т("rw_studio_flat") : (комнаты.isEmpty ? т("rw_flat") : комнаты + т("rw_rooms_flat"))
            if !площадь.isEmpty { итог += ", " + площадь + " м²" }
            if !этаж.isEmpty { итог += ", " + этаж + (этажей.isEmpty ? "" : "/" + этажей) + " " + т("rw_fl") }
            return итог
        case "house":
            var итог = т("rw_house")
            if !площадь.isEmpty { итог += ", " + площадь + " м²" }
            if !участок.isEmpty { итог += ", " + т("rw_plot_l") + " " + участок + " " + т("rw_sot") }
            return итог
        case "commercial":
            var итог = т("rw_premises")
            if !площадь.isEmpty { итог += ", " + площадь + " м²" }
            if !этаж.isEmpty { итог += ", " + этаж + " " + т("rw_fl") }
            return итог
        case "land":
            return т("rw_plot") + (участок.isEmpty ? "" : " " + участок + " " + т("rw_sot"))
        default:
            return ""
        }
    }

    func описаниеНедвижимости() -> String {
        var строки: [String] = []
        for поле in поляНедвижимости {
            if поле.вид == "toggle" {
                if форма.флагиНедвижимости[поле.id] == true { строки.append(поле.подпись) }
                continue
            }
            let значение = форма.недвижимость[поле.id] ?? ""
            guard !значение.isEmpty, поле.id != "owner" else { continue }
            if поле.id == "floors" && !(форма.недвижимость["floor"] ?? "").isEmpty { continue }
            var показ = поле.варианты.first(where: { $0.ключ == значение })?.подпись
                ?? (значение + (поле.единица.isEmpty ? "" : " " + поле.единица))
            if поле.id == "floor", let этажей = форма.недвижимость["floors"], !этажей.isEmpty { показ += "/" + этажей }
            строки.append(поле.подпись + ": " + показ)
        }
        return строки.joined(separator: "\n")
    }

    /// realtyMirror: площадь → storage, комнаты → ram («Студия»), «этаж/этажей» → cpu, участок → gpu, год → year.
    func зеркалоНедвижимости() -> [String: String] {
        let з = форма.недвижимость
        let комнаты = з["rooms"] ?? ""
        let этаж = з["floor"] ?? ""
        let этажей = з["floors"] ?? ""
        return [
            "storage": з["area"] ?? "",
            "ram": комнаты == "studio" ? "Студия" : комнаты,
            "cpu": этаж.isEmpty ? "" : этаж + (этажей.isEmpty ? "" : "/" + этажей),
            "gpu": з["land_area"] ?? "",
            "year": з["year_built"] ?? ""
        ]
    }

    // MARK: - Плашка

    /// toast сайта: короткая строка внизу, VoiceOver читает её сразу.
    func показать(_ текст: String) {
        let чистый = текст.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !чистый.isEmpty else { return }
        withAnimation(ДвижениеСайта.появление) { плашка = чистый }
        UIAccessibility.post(notification: .announcement, argument: чистый)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            guard self.плашка == чистый else { return }
            withAnimation(ДвижениеСайта.уход) { self.плашка = nil }
        }
    }

    // MARK: - Загрузка

    /**
     Страница кабинета (вход, токен, значения §0.7), справочники, потом — черновик (новое) или запись my_items (правка).
     Отдельного «получить объявление для правки» у сайта нет: showEdit берёт запись из списка my_items (§2.1.7).
     */
    func начать() async {
        экран = .загрузка
        do {
            let (состояние, html) = try await КабинетСайта.страницаКабинета()
            if состояние.вошёл == false {
                экран = .нуженВход
                return
            }
            МоиОбъявленияAPI.запомнитьТокен(состояние.csrf)
            страница = СтраницаПодачи.разобрать(html, состояние: состояние)
            справочники = try await ЗагрузкаСправочников.загрузить(страница)
            if правка {
                try await загрузитьПравку()
            } else {
                начатьНовое()
            }
        } catch {
            let сеть = (error as? КабинетСайта.Сбой) == .сеть
            экран = .ошибка(т(сеть ? "no_conn" : "load_err"))
        }
    }

    private func начатьНовое() {
        if let черновик = Self.прочитатьЧерновик() {
            вопрос = ВопросПодачи(заголовок: т("adr_t"), текст: т("adr_s") + "\n\n" + т("adr_cont") + " — " + т("adr_cont_s")
                                  + "\n" + т("adr_new") + " — " + т("adr_new_s"),
                                  да: т("adr_cont"), нет: т("adr_new"),
                                  действие: { [weak self] in self?.восстановить(черновик) },
                                  отказ: { [weak self] in
                                      ПодачаМодель.стеретьЧерновик()
                                      self?.показать(ПодачаText.т("draft_cleared"))
                                      self?.чистаяФорма()
                                  })
            экран = .старт
            return
        }
        чистаяФорма()
    }

    /// Пустая форма с тем, что сайт подставляет сам: гео и часы из настроек, гарант — по CAB_PREF_ESCROW_OFF.
    func чистаяФорма() {
        заполняем = true
        var ф = ФормаПодачи()
        ф.регион = страница.регион
        ф.район = страница.район
        ф.город = страница.город
        ф.адрес = страница.адрес
        ф.lat = страница.lat
        ф.lon = страница.lon
        ф.часы = страница.часы
        ф.часыС = страница.часыС
        ф.часыДо = страница.часыДо
        ф.гарант = !страница.гарантВыключен
        форма = ф
        плитки = []
        заполняем = false
        шаг = .фото
        старт = .корень
        экран = .старт
        мастер = nil
        мастерНедвижимостиБыл = false
        услуга = ЗаготовкаУслуги()
        обложкаПлитка = nil
    }

    private func восстановить(_ черновик: ЧерновикПодачи) {
        заполняем = true
        форма = черновик.форма
        /* ТОП при подаче в приложении не продаётся: старый выбор из черновика не оживает. */
        форма.топ = nil
        плитки = черновик.форма.фото.map { ПлиткаФото(id: UUID(), url: $0, превью: nil, картинка: nil, миниатюра: nil,
                                                      грузится: false, ошибка: nil) }
        /* Мастер услуги: направление, ответы и урл обложки — как были. */
        услуга = черновик.услуга ?? ЗаготовкаУслуги()
        обложкаПлитка = nil
        заполняем = false
        шаг = ШагПодачи(rawValue: черновик.шаг) ?? .фото
        /* Черновик уже заполняли — мастера сами не всплывают; открыть их можно карточкой параметров. */
        мастерНедвижимостиБыл = true
        экран = .шаги
        /* media_keep_alive — как у сайта при восстановлении черновика: продлить жизнь загруженным, но ещё не
           прикреплённым фото. Ответ сайт не читает. Зовём только после нажатия «Продолжить». */
        let адреса = черновик.форма.фото.filter { $0.contains("/img/uploads/") }
        if !адреса.isEmpty {
            Task { _ = try? await МоиОбъявленияAPI.отправить("cabinet.php?action=media_keep_alive", тело: ["urls": адреса]) }
        }
        показать(т("draft_back"))
    }

    // MARK: - Правка: запись my_items → форма (showEdit)

    private func загрузитьПравку() async throws {
        guard let j = try await МоиОбъявленияAPI.получить("cabinet.php?action=my_items") else {
            throw КабинетСайта.Сбой.приложение
        }
        if МоиОбъявленияAPI.нетСессии(j) {
            экран = .нуженВход
            return
        }
        let записи: [Any] = (j["items"] as? [Any]) ?? []
        guard let запись = записи.compactMap({ $0 as? [String: Any] })
            .first(where: { МоиОбъявленияAPI.строка($0["id"]) == номерПравки }) else {
            экран = .ошибка(т("edit_not_found"))
            return
        }
        заполнитьИз(запись)
        экран = .шаги
        шаг = .фото
    }

    private func заполнитьИз(_ з: [String: Any]) {
        typealias A = МоиОбъявленияAPI
        исходник = з
        заполняем = true
        var ф = ФормаПодачи()
        ф.название = A.строка(з["title"])
        ф.бренд = A.строка(з["brand"])
        ф.модель = A.строка(з["model"])
        ф.поколение = A.строка(з["gen"])
        ф.раздел = A.строка(з["category"])
        ф.описание = A.строка(з["description"])
        ф.cpu = A.строка(з["cpu"])
        ф.gpu = A.строка(з["gpu"])
        ф.ram = A.строка(з["ram"])
        ф.storage = A.строка(з["storage"])
        ф.year = A.строка(з["year"])
        ф.vin = A.строка(з["vin"]).uppercased()
        ф.состояние = A.строка(з["condition"]) == "new" ? "new" : "used"
        if let сломано = з["broken"] as? NSNumber {
            ф.работает = сломано.boolValue ? "bad" : "ok"
        }
        let цена = A.целое(з["price"])
        ф.цена = цена > 0 ? String(цена) : ""
        ф.торг = A.да(з["price_negotiable"])
        ф.аренда = A.да(з["for_rent"])
        ф.период = A.строка(з["rent_period"]) == "month" ? "month" : "day"
        let ставка = A.целое(з["rent_price_day"])
        ф.ставка = ставка > 0 ? String(ставка) : ""
        let залог = A.целое(з["rent_deposit"])
        ф.залог = залог > 0 ? String(залог) : ""
        let мин = A.целое(з["rent_min_days"])
        ф.минСрок = String(max(1, мин))
        ф.комплект = A.строка(з["rent_kit"])
        ф.тожеПродаю = A.да(з["also_sell"])
        ф.обмен = A.да(з["for_exchange"])
        let склад = A.целое(з["stock"])
        ф.склад = склад > 0 ? String(склад) : ""
        ф.гарант = !A.да(з["escrow_off"])
        ф.регион = A.строка(з["region"])
        ф.район = A.строка(з["district"])
        ф.город = A.строка(з["city"])
        ф.адрес = A.строка(з["address"])
        ф.lat = A.строка(з["lat"])
        ф.lon = A.строка(з["lon"])
        ф.часы = A.строка(з["hours_mode"])
        ф.часыС = A.строка(з["hours_from"])
        ф.часыДо = A.строка(з["hours_to"])
        ф.часыВыбраны = !ф.часы.isEmpty
        if let realty = з["realty"] as? [String: Any], !A.строка(realty["kind"]).isEmpty {
            ф.сделка = A.строка(realty["deal"])
            ф.вид = A.строка(realty["kind"])
            for (ключ, значение) in realty where ключ != "deal" && ключ != "kind" && ключ != "plan" {
                /* Переключатель (mortgage_ok…) сайт пишет true/false; NSNumber(1) из «rooms: 1» — не флаг, а число. */
                if let число = значение as? NSNumber, CFGetTypeID(число) == CFBooleanGetTypeID() {
                    ф.флагиНедвижимости[ключ] = число.boolValue
                } else {
                    ф.недвижимость[ключ] = A.строка(значение)
                }
            }
        }
        форма = ф
        let адреса: [String] = ((з["images"] as? [Any]) ?? []).map { A.строка($0) }.filter { !$0.isEmpty }
        плитки = адреса.map { ПлиткаФото(id: UUID(), url: $0, превью: nil, картинка: nil, миниатюра: nil,
                                         грузится: false, ошибка: nil) }
        let топДо = A.строка(з["top_until"])
        топВПравке = A.да(з["top"]) && ПодачаМодель.вБудущем(топДо)
        автоНазвание = ф.название
        автоОписание = ф.описание
        исходнаяФорма = ф
        исходныеФото = адреса
        заполняем = false
    }

    /// Date.parse(top_until) > сейчас: сервер пишет «2026-10-01 12:00:00» или ISO.
    static func вБудущем(_ дата: String) -> Bool {
        let чистая = дата.trimmingCharacters(in: .whitespaces)
        guard !чистая.isEmpty else { return false }
        let iso = ISO8601DateFormatter()
        if let д = iso.date(from: чистая) { return д > Date() }
        let ф = DateFormatter()
        ф.locale = Locale(identifier: "en_US_POSIX")
        ф.timeZone = TimeZone(identifier: "Asia/Almaty")
        for шаблон in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"] {
            ф.dateFormat = шаблон
            if let д = ф.date(from: чистая) { return д > Date() }
        }
        return false
    }

    // MARK: - Черновик (ulx_draft_add)

    struct ЧерновикПодачи: Codable {
        var форма: ФормаПодачи
        var шаг: Int
        var время: Double
        /// Ответы мастера услуги (старые черновики — без них).
        var услуга: ЗаготовкаУслуги? = nil
    }

    /// _addHasContent сайта: есть фото, название, описание, цена или бренд.
    private var естьЧтоСохранить: Bool {
        !готовыеФото.isEmpty || !форма.название.trimmingCharacters(in: .whitespaces).isEmpty
            || !форма.описание.trimmingCharacters(in: .whitespaces).isEmpty || !форма.цена.isEmpty
            || !форма.бренд.trimmingCharacters(in: .whitespaces).isEmpty
            || (режим == .услуга && услуга.естьОтветы)
    }

    /// Через 400 мс после изменения, как addDraftSave сайта. Правка черновика не пишет.
    func запланироватьЧерновик() {
        guard !правка, !заполняем, экран == .шаги else { return }
        черновикЗадача?.cancel()
        черновикЗадача = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, let модель = self else { return }
            модель.записатьЧерновик()
        }
    }

    func записатьЧерновик() {
        guard !правка, экран == .шаги else { return }
        /* Мастер уже закрыт выходом или удачной подачей — запоздалая запись не вернёт стёртый черновик. */
        guard ПодачаОкно.shared.цель == цель else { return }
        guard естьЧтоСохранить else {
            Self.стеретьЧерновик()
            return
        }
        var ф = форма
        ф.фото = готовыеФото
        var черновик = ЧерновикПодачи(форма: ф, шаг: шаг.rawValue, время: Date().timeIntervalSince1970)
        if режим == .услуга { черновик.услуга = услуга }
        if let данные = try? JSONEncoder().encode(черновик) {
            UserDefaults.standard.set(данные, forKey: Self.ключЧерновика)
        }
    }

    static func прочитатьЧерновик() -> ЧерновикПодачи? {
        guard let данные = UserDefaults.standard.data(forKey: ключЧерновика),
              var черновик = try? JSONDecoder().decode(ЧерновикПодачи.self, from: данные) else { return nil }
        guard Date().timeIntervalSince1970 - черновик.время < срокЧерновика else {
            стеретьЧерновик()
            return nil
        }
        черновик.форма.обрезатьДлины()
        return черновик
    }

    /// После подачи и при выходе (ВыходНачисто): черновик одного человека следующему не достаётся.
    static func стеретьЧерновик() {
        UserDefaults.standard.removeObject(forKey: ключЧерновика)
    }

    func остановить() {
        черновикЗадача?.cancel()
        ценаЗадача?.cancel()
    }

    // MARK: - Стартовый экран (_asPick сайта)

    /// Плитка корня.
    func выбратьПлитку(_ ключ: String) {
        switch ключ {
        case "goods": старт = .товар
        case "clothing": старт = .одежда
        case "animals": старт = .животные
        case "rentgood": старт = .аренда
        case "realty": старт = .сделка
        case "auto": старт = .транспорт
        case "services":
            применитьСтарт(тип: "services", раздел: "services", плитка: т("as_services"), подсказка: "",
                           подпись: т("as_services_s"))
        default:
            break
        }
    }

    /// Выбор внутри плитки: тип, раздел, подпись для recognize; у «Сдать вещь» сразу включается аренда.
    func применитьСтарт(тип: String, раздел: String, плитка: String, подсказка: String, период: String? = nil,
                        подпись: String = "") {
        var ф = форма
        ф.тип = тип
        ф.плитка = плитка
        ф.плиткаПодпись = подпись.isEmpty ? nil : подпись
        ф.подсказка = подсказка
        форма = ф
        выбратьРаздел(раздел)
        if тип == "rentgood" {
            форма.аренда = true
            if let период { форма.период = период }
        }
        if !плитки.isEmpty && плитки.count > лимитФото {
            показать(String(format: т("photos_kept"), лимитФото))
        }
        шаг = .фото
        экран = .шаги
        if тип == "services" { услуга = ЗаготовкаУслуги() }
        /* _asAutoGo: транспорт (кроме запчастей) — сразу мастер «Кузов → Марка → Модель → Поколение → Год и пробег →
           Коробка и топливо»; фото — после него. */
        if режим == .авто && !правка {
            открытьМастерПозже(.авто(кузов: true))
        }
    }

    /// Мастер — когда шаги уже на экране (окно поверх появляющегося экрана SwiftUI может не показать).
    private func открытьМастерПозже(_ м: МастерПодачи) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let модель = self, модель.экран == .шаги, модель.мастер == nil else { return }
            модель.мастер = м
        }
    }

    /// _asRealtyGo: сделка и вид; сдача — сразу аренда.
    func применитьНедвижимость(сделка: String, вид: String, раздел: String) {
        var ф = форма
        ф.тип = "realty"
        ф.плитка = т("as_realty")
        ф.плиткаПодпись = nil
        ф.подсказка = "Это квартира или жилая недвижимость"
        ф.сделка = сделка
        ф.вид = вид
        ф.недвижимость = ["owner": "owner"]
        ф.флагиНедвижимости = [:]
        ф.аренда = сделка == "rent"
        форма = ф
        выбратьРаздел(раздел)
        шаг = .фото
        экран = .шаги
        /* _asRealtyGo: сделка и вид выбраны на старте — мастер объекта сразу со второго шага (параметры). */
        мастерНедвижимостиБыл = true
        открытьМастерПозже(.недвижимость(сШага: 1))
    }

    /// «Изменить» на полосе типа — снова стартовый экран (форма остаётся).
    func сменитьТип() {
        мастер = nil
        старт = .корень
        экран = .старт
    }

    // MARK: - Цена по рынку (/api/price_stats.php, только чтение)

    private func запланироватьРынок() {
        ценаЗадача?.cancel()
        let раздел = форма.раздел
        guard !раздел.isEmpty, раздел != "other", !услугаИлиРабота else {
            рынок = nil
            return
        }
        ценаЗадача = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled, let модель = self else { return }
            await модель.узнатьРынок()
        }
    }

    private func узнатьРынок() async {
        let раздел = форма.раздел
        let город = форма.город
        let ключ = раздел + "|" + город
        let цена = ценаЧислом
        func код(_ с: String) -> String { с.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? с }
        let ответ: [String: Any]?
        if ключ == последнийРынок, let был = кэшРынка {
            ответ = был
        } else {
            ответ = try? await МоиОбъявленияAPI.получить("/api/price_stats.php?category=" + код(раздел) + "&city=" + код(город),
                                                        отКорня: true)
            последнийРынок = ключ
            кэшРынка = ответ
        }
        guard let j = ответ, МоиОбъявленияAPI.да(j["ok"]), МоиОбъявленияAPI.да(j["enough"]),
              МоиОбъявленияAPI.целое(j["count"]) >= 2 else {
            рынок = nil
            return
        }
        let сколько = МоиОбъявленияAPI.целое(j["count"])
        let низ = МоиОбъявленияAPI.целое(j["mkt_min"])
        let среднее = МоиОбъявленияAPI.целое(j["avg"])
        let верх = МоиОбъявленияAPI.целое(j["mkt_max"])
        if подсказкаЦены == nil || подсказкаЦены?.подпись.hasPrefix(т("market_word")) == true {
            подсказкаЦены = ПодсказкаЦены(подпись: т("market_word") + " · " + String(сколько), низ: низ,
                                          середина: среднее, верх: верх)
        }
        var текст = String(format: т("ps_line"), String(сколько), Self.деньги(низ), Self.деньги(верх), Self.деньги(среднее))
        рынокДорого = false
        if цена > 0 && среднее > 0 {
            let доля = Int((Double(цена - среднее) / Double(среднее) * 100).rounded())
            if доля > 20 {
                текст += "\n" + String(format: т("ps_above"), доля)
                рынокДорого = true
            } else if доля < -20 {
                текст += "\n" + String(format: т("ps_below"), abs(доля))
            } else {
                текст += "\n" + т("ps_in")
            }
        }
        рынок = текст
    }

    private var кэшРынка: [String: Any]? = nil

    /// «150 000» — пробелы между тысячами, как numFmt сайта.
    nonisolated static func деньги(_ число: Int) -> String {
        let ф = NumberFormatter()
        ф.numberStyle = .decimal
        ф.groupingSeparator = " "
        ф.usesGroupingSeparator = true
        ф.maximumFractionDigits = 0
        return ф.string(from: NSNumber(value: число)) ?? String(число)
    }

    // MARK: - «Этого уже ждут» (/subs.php?action=reach, только чтение)

    /// Сайт спрашивает через 700 мс после любого ввода; здесь — при входе на «Проверку», один раз на набор полей.
    func узнатьОхват() {
        guard !правка else { return }
        let тело: [String: Any] = ["category": форма.раздел, "city": форма.город, "price": ценаЧислом,
                                   "condition": форма.состояние, "brand": форма.бренд, "title": форма.название]
        guard !форма.раздел.isEmpty || !форма.название.isEmpty else {
            ждут = 0
            return
        }
        let ключ = [форма.раздел, форма.город, String(ценаЧислом), форма.состояние, форма.бренд, форма.название]
            .joined(separator: "|")
        guard ключ != последнийОхват else { return }
        последнийОхват = ключ
        Task { @MainActor [weak self] in
            let j = try? await МоиОбъявленияAPI.отправить("/subs.php?action=reach", тело: тело, отКорня: true)
            guard let модель = self else { return }
            модель.ждут = (j.map { МоиОбъявленияAPI.да($0["ok"]) } ?? false) ? МоиОбъявленияAPI.целое(j?["n"]) : 0
        }
    }
}

/// Модель авто из /api/auto_models.php?brand=: имя, поколения {name, from, to} и кузова body (разделы cars-*).
struct МодельАвто: Equatable, Identifiable {
    let имя: String
    let поколения: [ПоколениеАвто]
    let кузов: [String]
    var id: String { имя }
}

/// Группа марок справочника (region у /api/auto_models.php?brands=1): подпись и марки по порядку сайта.
struct ГруппаМарок: Equatable, Identifiable {
    let регион: String
    let марки: [String]
    var id: String { регион }
}

/// Мастер поверх шагов: авто (autoWizOpen; кузов — уточнение _asRenderAutoKids перед маркой, только со старта) и
/// недвижимость (realtyWizOpen; сШага 1 — сделка и вид уже выбраны на старте).
enum МастерПодачи: Identifiable, Equatable {
    case авто(кузов: Bool)
    case недвижимость(сШага: Int)

    var id: String {
        switch self {
        case .авто(let кузов): return кузов ? "auto-body" : "auto"
        case .недвижимость(let с): return "realty-" + String(с)
        }
    }
}

struct ПоколениеАвто: Equatable, Identifiable {
    let имя: String
    let с: Int
    let по: Int
    var id: String { имя + "|" + String(с) }
}
