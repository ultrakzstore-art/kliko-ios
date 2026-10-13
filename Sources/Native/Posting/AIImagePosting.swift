import SwiftUI
import UIKit

/**
 ИИ-ФОТО В ПОДАЧЕ — ЧТО ИИ СДЕЛАЛ В ЭТОМ ОБЪЯВЛЕНИИ, ВХОДЫ И ПРАВИЛО ДОВЕРИЯ (docs/SERVER_AI_IMAGE.md §8–9).

 Запись на цель подачи («new» или «edit:<id>»), на телефоне, вместе с черновиком подачи: диалог (thread), принятый
 черновик ИИ (draft_id и «Проверил характеристики»), пометки взятых фото (адрес → illustration | edited). Чужому
 человеку (другой id сессии) запись не достаётся. Диалог удаляется на сервере после удачной публикации и когда подача
 начинается заново; закрытие окна чата его не удаляет — можно вернуться (сервер сам сотрёт его через сутки).

 Правило доверия (рекомендация; итог — рубильники сервера в info.types):
   · у взятой картинки — плашка: «Иллюстрация ИИ» (нарисована по описанию — не фото товара) или «Изменено ИИ»;
   · вид требует настоящего фото (require_real_photo), а среди фото только иллюстрация — подсказка «Добавьте хотя бы
     одно своё фото» до публикации; ответ сервера need_real_photo — окончательный;
   · поля пришли из черновика ИИ — перед публикацией галочка «Проверил характеристики»; без неё «Опубликовать» не
     уходит, а в submit идут ai_draft и ai_checked.
 Входы: карточка на выборе способа подачи, карточка на шаге «Фото», пункт меню плитки фото — только при рубильнике
 Config.ииРедакторФото и ответе info.
 */

// MARK: - Запись подачи

struct ЗаписьИИФотоПодачи: Codable, Equatable {
    /// thread диалога; пусто — диалога нет.
    var диалог = ""
    /// draft_id принятого черновика (accept_draft); «local» — поля из ИИ, а сервер id не дал (галочка всё равно нужна,
    /// ai_draft не уходит); пусто — поля не из черновика ИИ.
    var черновик = ""
    var проверил = false
    /// unsure черновика — ключи характеристик, в которых ИИ не уверен.
    var неуверенные: [String] = []
    /// Адрес взятого фото → illustration | edited.
    var метки: [String: String] = [:]
    var время: Double = 0
}

/// Что лежит на телефоне: чьи записи и сами записи по целям подачи.
private struct ХранилищеИИФотоПодачи: Codable {
    var кто: String
    var записи: [String: ЗаписьИИФотоПодачи]
}

/// Слабая ссылка на подачу: подача, где выбор способа уже начинал всё заново, не держится в памяти.
final class СлабаяПодачаИИФото {
    weak var подача: ПодачаМодель?

    init(_ подача: ПодачаМодель) {
        self.подача = подача
    }
}

@MainActor
final class ИИФотоПодачи: ObservableObject {
    static let shared = ИИФотоПодачи()

    /// Растёт при каждой записи: экраны (плашки плиток, галочка) перечитывают себя. Чтение записей его не трогает —
    /// их можно читать прямо из body.
    @Published private(set) var версия = 0

    private var записи: [String: ЗаписьИИФотоПодачи] = [:]
    private var кто = ""
    private var прочитано = false
    private var начатыеЗаново: [СлабаяПодачаИИФото] = []

    private static let ключ = "kliko.aiimage.posting.v1"
    /// Как у черновика подачи — 7 дней.
    private static let срок: TimeInterval = 7 * 24 * 3600

    private init() {}

    private func ключЦели(_ подача: ПодачаМодель) -> String { подача.цель.id }

    /// Кто подаёт: uid страницы кабинета подачи, иначе id сессии приложения; пусто — ещё не знаем.
    private func ктоПодаёт(_ подача: ПодачаМодель) -> String {
        let uid = подача.страница.состояние?.uid ?? ""
        return uid.isEmpty ? СессияПриложения.shared.id : uid
    }

    /**
     Записи с телефона — один раз на человека; сменился человек — чужие записи не показываем и стираем. Пока не знаем,
     кто это (пустой id), — записи только в памяти: чужое не показываем, своё не стираем.
     */
    private func прочитать(_ подача: ПодачаМодель) {
        let сейчас = ктоПодаёт(подача)
        if прочитано && кто == сейчас { return }
        записи = [:]
        кто = сейчас
        guard !сейчас.isEmpty else {
            прочитано = false
            return
        }
        прочитано = true
        guard let данные = UserDefaults.standard.data(forKey: Self.ключ),
              let хранилище = try? JSONDecoder().decode(ХранилищеИИФотоПодачи.self, from: данные) else { return }
        guard хранилище.кто == сейчас else {
            UserDefaults.standard.removeObject(forKey: Self.ключ)
            return
        }
        let граница = Date().timeIntervalSince1970 - Self.срок
        записи = хранилище.записи.filter { $0.value.время > граница }
    }

    private func записать() {
        guard !кто.isEmpty else { return }
        let пустые = записи.filter { $0.value.диалог.isEmpty && $0.value.черновик.isEmpty && $0.value.метки.isEmpty }
        for (ключ, _) in пустые { записи[ключ] = nil }
        guard !записи.isEmpty else {
            UserDefaults.standard.removeObject(forKey: Self.ключ)
            return
        }
        if let данные = try? JSONEncoder().encode(ХранилищеИИФотоПодачи(кто: кто, записи: записи)) {
            UserDefaults.standard.set(данные, forKey: Self.ключ)
        }
    }

    func запись(_ подача: ПодачаМодель) -> ЗаписьИИФотоПодачи {
        прочитать(подача)
        return записи[ключЦели(подача)] ?? ЗаписьИИФотоПодачи()
    }

    private func изменить(_ подача: ПодачаМодель, _ правка: (inout ЗаписьИИФотоПодачи) -> Void) {
        прочитать(подача)
        var з = записи[ключЦели(подача)] ?? ЗаписьИИФотоПодачи()
        правка(&з)
        з.время = Date().timeIntervalSince1970
        записи[ключЦели(подача)] = з
        записать()
        версия += 1
    }

    /// Запись цели — прочь: диалог на сервере удаляется, на телефоне не остаётся ничего.
    private func стереть(_ подача: ПодачаМодель) {
        прочитать(подача)
        guard let з = записи[ключЦели(подача)] else { return }
        удалитьНаСервере(з.диалог)
        записи[ключЦели(подача)] = nil
        записать()
        версия += 1
    }

    // MARK: Диалог

    func диалог(_ подача: ПодачаМодель) -> String { запись(подача).диалог }

    func запомнитьДиалог(_ подача: ПодачаМодель, _ диалог: String) {
        guard !диалог.isEmpty, запись(подача).диалог != диалог else { return }
        изменить(подача) { $0.диалог = диалог }
    }

    /// Только на телефоне (сервер сказал gone или диалог уже удалён).
    func забытьДиалог(_ подача: ПодачаМодель) {
        guard !запись(подача).диалог.isEmpty else { return }
        изменить(подача) { $0.диалог = "" }
    }

    /// delete на сервер без ожидания: не дошёл — сервер сотрёт диалог сам через сутки.
    private func удалитьНаСервере(_ диалог: String) {
        guard !диалог.isEmpty, Config.ииРедакторФото else { return }
        Task { @MainActor in _ = await ИИФотоAPI.удалить(диалог) }
    }

    // MARK: Фото и черновик

    func пометка(_ подача: ПодачаМодель, адрес: String) -> String? {
        guard !адрес.isEmpty else { return nil }
        return запись(подача).метки[адрес]
    }

    func отметитьФото(_ подача: ПодачаМодель, адрес: String, вид: String) {
        guard !адрес.isEmpty, ["illustration", "edited"].contains(вид) else { return }
        изменить(подача) { $0.метки[адрес] = вид }
    }

    /// Черновик ИИ без draft_id от сервера: поля всё равно из ИИ — галочка нужна, но ai_draft не уходит.
    static let черновикБезID = "local"

    /// Поля черновика ИИ легли в форму: перед публикацией — «Проверил характеристики» (даже если сервер не дал id).
    func принятьЧерновик(_ подача: ПодачаМодель, id: String, неуверенные: [String]) {
        let номер = id.trimmingCharacters(in: .whitespacesAndNewlines)
        изменить(подача) { з in
            з.черновик = номер.isEmpty ? Self.черновикБезID : номер
            з.проверил = false
            з.неуверенные = неуверенные
        }
    }

    func отметитьПроверку(_ подача: ПодачаМодель, _ проверил: Bool) {
        guard !запись(подача).черновик.isEmpty else { return }
        изменить(подача) { $0.проверил = проверил }
    }

    // MARK: Публикация

    /// Поля из черновика ИИ, а галочки нет — текст для строки под ней; иначе nil.
    func нужнаГалочка(_ подача: ПодачаМодель) -> String? {
        guard Config.ииРедакторФото, !подача.правка else { return nil }
        let з = запись(подача)
        guard !з.черновик.isEmpty, !з.проверил else { return nil }
        return ИИФотоText.т("aim_check_need")
    }

    /// ai_draft и ai_checked в submit — всегда вместе (договор §9.4).
    func поляПодачи(_ подача: ПодачаМодель) -> [String: Any] {
        guard Config.ииРедакторФото, !подача.правка else { return [:] }
        let з = запись(подача)
        guard !з.черновик.isEmpty, з.черновик != Self.черновикБезID, з.проверил else { return [:] }
        return ["ai_draft": з.черновик, "ai_checked": 1]
    }

    /// Объявление сохранено: диалог на сервере больше не нужен, запись этой цели — тоже.
    func послеПубликации(_ подача: ПодачаМодель) {
        guard Config.ииРедакторФото else { return }
        стереть(подача)
    }

    /**
     Выбор способа подачи с чистой формой (новая подача или «Начать заново»): прежний диалог новой подачи — на сервере
     удалить, запись — стереть. Один раз на открытую подачу: возврат к выбору после чата запись не трогает.
     */
    func начатьЗаново(_ подача: ПодачаМодель) {
        guard Config.ииРедакторФото, !подача.правка else { return }
        начатыеЗаново.removeAll { $0.подача == nil }
        guard !начатыеЗаново.contains(where: { $0.подача === подача }) else { return }
        начатыеЗаново.append(СлабаяПодачаИИФото(подача))
        guard подача.плитки.isEmpty, подача.форма.название.isEmpty else { return }
        стереть(подача)
    }

    /**
     Отказ submit / edit_item по правилу доверия: need_real_photo — вопрос «Добавьте хотя бы одно своё фото» и шаг
     «Фото»; need_check — строка под галочкой и окно проверки снова. true — отказ разобран.
     */
    func разобратьОтказПодачи(_ j: [String: Any], подача: ПодачаМодель) -> Bool {
        typealias A = МоиОбъявленияAPI
        let код = A.строка(j["code"])
        let ошибка = A.строка(j["error"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let текстСервера = ошибка.isEmpty || КабинетСайта.машинныйКод(ошибка) ? "" : ошибка
        if код == "need_real_photo" || A.да(j["need_real_photo"]) {
            let т = ИИФотоText.т
            let причина = A.строка(j["reason"])
            let запасной = причина == "max" ? т("aim_real_max") : т("aim_real_need")
            подача.вопрос = ВопросПодачи(заголовок: т("aim_real_t"), текст: текстСервера.isEmpty ? запасной : текстСервера,
                                        да: т("aim_real_add"), нет: т("aim_later"),
                                        действие: { [weak подача] in подача?.кФотоИИ() })
            return true
        }
        if код == "need_check" {
            отметитьПроверку(подача, false)
            let текст = текстСервера.isEmpty ? ИИФотоText.т("aim_check_need") : текстСервера
            подача.пометить("ai_check", текст)
            подача.подтверждение = true
            return true
        }
        return false
    }
}

// MARK: - Подача

extension ПодачаМодель {
    /// Вид объявления по форме (ключи types договора). nil — раздел ещё не выбран.
    var видИИФото: String? {
        switch режим {
        case .работа: return "jobs"
        case .недвижимость: return "realty"
        case .авто: return "transport"
        case .услуга: return "services"
        case .товар, .запчасти:
            if форма.раздел.isEmpty && форма.тип.isEmpty { return nil }
            if форма.аренда || форма.тип == "rentgood" { return "rentgood" }
            return форма.состояние == "new" ? "goods_new" : "goods_used"
        }
    }

    /// Плашка у плитки: illustration | edited | nil. Свои пометки (картинки, взятые в этой подаче) и — в правке
    /// опубликованного — пометки сервера из my_items.images_meta (договор §9.1).
    func пометкаИИ(_ плитка: ПлиткаФото) -> String? {
        guard Config.ииРедакторФото, плитка.готова else { return nil }
        if let своя = ИИФотоПодачи.shared.пометка(self, адрес: плитка.url) { return своя }
        return меткиСервераИИ?[плитка.url]
    }

    /// Правка: адрес фото → illustration | edited по images_meta записи my_items (та же длина и порядок, что images).
    /// nil — не правка или сервер поля не прислал.
    var меткиСервераИИ: [String: String]? {
        typealias A = МоиОбъявленияAPI
        guard правка, let меты = исходник["images_meta"] as? [Any] else { return nil }
        let адреса = (исходник["images"] as? [Any]) ?? []
        var итог: [String: String] = [:]
        for (номер, элемент) in меты.enumerated() where номер < адреса.count {
            guard let мета = элемент as? [String: Any] else { continue }
            let вид = A.строка(мета["ai"])
            let адрес = A.строка(адреса[номер])
            if !адрес.isEmpty && ["illustration", "edited"].contains(вид) { итог[адрес] = вид }
        }
        return итог
    }

    /**
     Пометки ИИ у фото известны: новая подача — свои, на телефоне; правка — сервер прислал images_meta (в my_items оно
     есть всегда, хоть из null, §9.1) или генератора на сервере нет вовсе. Не известны — на фото правки нет ни «Править
     с ИИ», ни студии: иллюстрацию с сайта нельзя переснять в «настоящее фото».
     */
    var меткиИИИзвестны: Bool {
        guard Config.ииРедакторФото, правка else { return true }
        return исходник["images_meta"] is [Any] || ГотовностьИИФото.shared.нетСервера
    }

    /**
     Студия (PhotoStudio*) на плитке — со стороны ИИ-фото: не картинка ИИ и пометки известны. Иначе готовый кадр студии
     ушёл бы через upload_photo новым адресом, без пометки: иллюстрация засчиталась бы настоящим фото.
     */
    func студияБезИИ(_ плитка: ПлиткаФото) -> Bool {
        пометкаИИ(плитка) == nil && меткиИИИзвестны
    }

    /// Плитка для плашки «Сделать как в каталоге»: первая, которую можно открыть в студии, и не картинка ИИ.
    var плиткаПлашкиСтудииБезИИ: ПлиткаФото? {
        guard плиткаДляПлашкиСтудии != nil else { return nil }
        return плитки.first { студияДоступна($0) && студияБезИИ($0) }
    }

    /// Иллюстраций ИИ среди фото подачи (кроме — плитка, которую сейчас заменяют).
    func иллюстрацийИИ(кроме: UUID? = nil) -> Int {
        плитки.filter { $0.id != кроме && пометкаИИ($0) == "illustration" }.count
    }

    /// Правку ИИ можно открыть на плитке: сервер готов, вид разрешает, фото загружено, это не иллюстрация и не постер;
    /// в правке опубликованного — только когда пометки сервера известны (меткиИИИзвестны).
    func правкаИИДоступна(_ плитка: ПлиткаФото) -> Bool {
        guard Config.ииРедакторФото, плитка.готова, !плитка.грузится, плитка.ошибка == nil, !этоОбложка(плитка) else {
            return false
        }
        guard пометкаИИ(плитка) != "illustration", меткиИИИзвестны else { return false }
        return ГотовностьИИФото.shared.правкаДоступна(вид: видИИФото)
    }

    /**
     Подсказка перед публикацией по правилу вида (info.types): среди фото есть иллюстрация ИИ, а вид требует настоящего
     фото — или иллюстраций больше max_illustrations. nil — всё в порядке или сведений нет (тогда решит сервер).
     */
    var подсказкаНастоящегоФотоИИ: String? {
        guard Config.ииРедакторФото, let с = ГотовностьИИФото.shared.сведения else { return nil }
        let иллюстраций = иллюстрацийИИ()
        guard иллюстраций > 0 else { return nil }
        if иллюстраций > с.иллюстрацийМакс { return ИИФотоText.т("aim_real_max") }
        guard let вид = видИИФото, с.правила(вид).нужноНастоящее else { return nil }
        let настоящих = плитки.filter { п in
            guard п.готова else { return false }
            let м = пометкаИИ(п)
            if м == "illustration" { return false }
            if м == "edited" { return с.правкаНастоящая }
            return true
        }.count
        return настоящих == 0 ? ИИФотоText.т("aim_real_need") : nil
    }

    /// «Добавить фото»: к фото подачи — на короткой подаче камера, иначе шаг «Фото».
    func кФотоИИ() {
        подтверждение = false
        if быстрый && !правка {
            кКамере()
        } else {
            шаг = .фото
            if экран != .шаги { экран = .шаги }
        }
    }

    /**
     Черновик ИИ (accept_draft) — в форму тем же путём, что ответ «Распознать» (принятьПоляЧерновикаИИ, PostingSend):
     поля — предложения, цену форма сама не ставит. С выбора способа: раздел знаком — шаги с «Фото» (ответ «Распознать»
     сам переведёт на «Данные»), незнаком — «Что размещаете?»: поля останутся.
     */
    func применитьЧерновикИИ(_ поля: [String: Any]) {
        let раздел = МоиОбъявленияAPI.строка(поля["category"])
        let знаком = !раздел.isEmpty && справочники.разделы[раздел] != nil
        if !правка && экран != .шаги {
            if знаком && форма.тип.isEmpty {
                let корень = справочники.корень(раздел)
                if корень == "services" {
                    форма.тип = "services"
                } else if корень == "realty" {
                    форма.тип = "realty"
                } else if корень != "transport" || справочники.внутри(раздел, ["auto-parts"]) {
                    форма.тип = "goods"
                }
            }
            быстрый = false
            шаг = .фото
            if знаком {
                экран = .шаги
            } else {
                безФото()
            }
        }
        принятьПоляЧерновикаИИ(поля)
    }
}

// MARK: - Окно чата поверх подачи

/// Как открыть чат: «Объявление по названию» или правка фото плитки.
enum ВходЧатаИИФото: Identifiable, Equatable {
    case черновик
    case правка(UUID)

    var id: String {
        switch self {
        case .черновик: return "draft"
        case .правка(let плитка): return "edit:" + плитка.uuidString
        }
    }
}

/// Полноэкранный чат поверх шага: вход не nil — окно открыто.
struct ПоказЧатаИИФото: ViewModifier {
    let подача: ПодачаМодель
    @Binding var вход: ВходЧатаИИФото?

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $вход) { выбранный in
                ЭкранЧатаИИФото(подача: подача, вход: выбранный, закрыть: { вход = nil })
            }
    }
}

extension View {
    /// Окно «Объявление с ИИ» для подачи; `вход` — как открыть или nil.
    func чатИИФото(подача: ПодачаМодель, вход: Binding<ВходЧатаИИФото?>) -> some View {
        modifier(ПоказЧатаИИФото(подача: подача, вход: вход))
    }
}

// MARK: - Входы

/**
 Выбор способа подачи («Быстро» / «Подробно»): заметная карточка «Создать объявление с ИИ» — зелёный градиент, значок
 палочки, по карточке пробегает блик (при «Уменьшении движения» — нет). Нет рубильника или ответа info — ничего.
 */
struct КарточкаИИВыбораПодачи: View {
    @ObservedObject var модель: ПодачаМодель
    @ObservedObject private var готовность = ГотовностьИИФото.shared
    @State private var вход: ВходЧатаИИФото? = nil
    @State private var блик = false
    @Environment(\.accessibilityReduceMotion) private var меньшеДвижения

    init(модель: ПодачаМодель) {
        self.модель = модель
    }

    private func т(_ ключ: String) -> String { ИИФотоText.т(ключ) }

    private var тихо: Bool { меньшеДвижения || ДвижениеСайта.тихо }

    var body: some View {
        /* Пока чат открыт, карточка держится: окно чата висит на ней. */
        if Config.ииРедакторФото && !модель.правка && (готовность.черновикДоступен || вход != nil) {
            кнопка
                .чатИИФото(подача: модель, вход: $вход)
                .transition(.opacity)
        }
    }

    private var кнопка: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
        return Button {
            ОткликСайта.выбор()
            вход = .черновик
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "wand.and.stars")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.зелёный2)
                    .frame(width: 48, height: 48)
                    .background(Color.white, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(т("aim_start_t"))
                            .font(.headline.weight(.heavy))
                            .foregroundStyle(Color.white)
                            .multilineTextAlignment(.leading)
                        Text(т("aim_new"))
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(Theme.зелёный2)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.white, in: Capsule())
                    }
                    Text(т("aim_start_s"))
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.9))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .padding(.top, 4)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [Theme.кнопкаКамерыНачало, Theme.кнопкаКамерыКонец],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), in: форма)
            .overlay { отблеск.clipShape(форма) }
            .shadow(color: Color(uiColor: Theme.hex(0x0F5132, 0.3)), radius: 10, y: 6)
            .contentShape(форма)
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
        .accessibilityHint(т("aim_start_s"))
        .onAppear {
            guard !тихо else { return }
            блик = true
        }
    }

    private static let бегБлика = Animation.easeInOut(duration: 1.6).delay(1.2).repeatForever(autoreverses: false)

    private var отблеск: some View {
        GeometryReader { г in
            LinearGradient(colors: [Color.white.opacity(0), Color.white.opacity(0.32), Color.white.opacity(0)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: 80)
                .rotationEffect(.degrees(18))
                .offset(x: блик ? г.size.width + 90 : -160)
                .animation(блик ? Self.бегБлика : nil, value: блик)
        }
        .opacity(тихо ? 0 : 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Шаг «Фото» новой подачи: «Объявление по названию» — тот же чат (режим А). Нет рубильника или ответа info — ничего.
struct ВходИИФотоВШаге: View {
    @ObservedObject var модель: ПодачаМодель
    let открыть: () -> Void
    @ObservedObject private var готовность = ГотовностьИИФото.shared

    init(модель: ПодачаМодель, открыть: @escaping () -> Void) {
        self.модель = модель
        self.открыть = открыть
    }

    private func т(_ ключ: String) -> String { ИИФотоText.т(ключ) }

    var body: some View {
        if Config.ииРедакторФото && готовность.черновикДоступен && !модель.правка {
            Button {
                ОткликСайта.выбор()
                открыть()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(width: 40, height: 40)
                        .background(LinearGradient(colors: [Theme.кнопкаКамерыНачало, Theme.кнопкаКамерыКонец],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(т("aim_step_t"))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(КраскаПодачи.текст)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(т("aim_step_s"))
                            .font(.caption)
                            .foregroundStyle(Theme.текстВторой)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(КраскаПодачи.хорошоТекст)
                        .accessibilityHidden(true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(КраскаПодачи.хорошоФон, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                        .strokeBorder(КраскаПодачи.хорошоТекст.opacity(0.28), lineWidth: 1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
        }
    }
}

/// Пункт меню плитки фото — правка ИИ (рядом со «Студией»).
struct ПунктИИФотоПлитки: View {
    let действие: () -> Void

    init(действие: @escaping () -> Void) {
        self.действие = действие
    }

    var body: some View {
        Button(ИИФотоText.т("aim_menu_edit"), systemImage: "wand.and.stars", action: действие)
    }
}

/// Плашка на плитке и на картинке чата: «Иллюстрация ИИ» или «Изменено ИИ».
struct ПометкаИИФото: View {
    let вид: String
    var мелкая = true

    init(вид: String, мелкая: Bool = true) {
        self.вид = вид
        self.мелкая = мелкая
    }

    static func текст(_ вид: String) -> String {
        ИИФотоText.т(вид == "illustration" ? "aim_mark_ill" : "aim_mark_edit")
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: вид == "illustration" ? "paintbrush.pointed.fill" : "wand.and.rays")
                .font(.system(size: мелкая ? 8 : 11, weight: .bold))
                .accessibilityHidden(true)
            Text(Self.текст(вид))
                .font(мелкая ? .system(size: 9, weight: .bold) : .caption.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, мелкая ? 5 : 8)
        .padding(.vertical, мелкая ? 2 : 4)
        .background(Color.black.opacity(0.62), in: Capsule())
        .overlay { Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.текст(вид))
    }
}

// MARK: - Перед публикацией

/**
 Окно «Проверьте перед публикацией»: поля из черновика ИИ — галочка «Проверил характеристики» (ИИ мог ошибиться в
 модели; сомнительные — списком); среди фото иллюстрация, а вид требует настоящего — подсказка и «Добавить фото»;
 картинки ИИ в объявлении — тихая заметка, что у покупателя они будут с плашкой.
 */
struct ПроверкаИИПодачи: View {
    @ObservedObject var модель: ПодачаМодель
    @ObservedObject private var хранилище = ИИФотоПодачи.shared

    init(модель: ПодачаМодель) {
        self.модель = модель
    }

    private func т(_ ключ: String) -> String { ИИФотоText.т(ключ) }

    private var запись: ЗаписьИИФотоПодачи { хранилище.запись(модель) }

    private var естьКартинкиИИ: Bool {
        модель.плитки.contains { модель.пометкаИИ($0) != nil }
    }

    var body: some View {
        if Config.ииРедакторФото && !модель.правка {
            VStack(alignment: .leading, spacing: 10) {
                if !запись.черновик.isEmpty { галочка }
                if let подсказка = модель.подсказкаНастоящегоФотоИИ {
                    VStack(alignment: .leading, spacing: 8) {
                        ЗаметкаПодачи(подсказка, тон: .внимание, значок: "camera.badge.ellipsis")
                        КнопкаПодачиВторая(т("aim_real_add")) { модель.кФотоИИ() }
                    }
                }
                if естьКартинкиИИ {
                    ЗаметкаПодачи(т("aim_marked_note"), тон: .серый, значок: "wand.and.stars")
                }
            }
        }
    }

    private var проверил: Binding<Bool> {
        Binding(get: { хранилище.запись(модель).проверил }, set: { новое in
            хранилище.отметитьПроверку(модель, новое)
            if новое { модель.ошибкиПолей["ai_check"] = nil }
            ОткликСайта.выбор()
        })
    }

    private var галочка: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: проверил) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(т("aim_check_t"))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(КраскаПодачи.текст)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(подписьГалочки)
                        .font(.caption)
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(ГалочкаИИФото())
            .padding(12)
            .background(запись.проверил ? КраскаПодачи.хорошоФон : КраскаПодачи.вниманиеФон,
                        in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                    .strokeBorder(запись.проверил ? КраскаПодачи.хорошоТекст.opacity(0.4) : КраскаПодачи.вниманиеКромка,
                                  lineWidth: 1)
            }
            СтрокаОшибки(модель.ошибка("ai_check"))
        }
        .id("ai_check")
    }

    /// «ИИ мог ошибиться в модели» и сомнительные характеристики по подписям схемы раздела.
    private var подписьГалочки: String {
        let подписи = Dictionary(модель.характеристики.map { ($0.поле, $0.подпись) }, uniquingKeysWith: { a, _ in a })
        let сомнительные = запись.неуверенные.compactMap { ключ -> String? in
            if ключ == "cond" { return т("aim_unsure_cond") }
            return подписи[ключ]
        }
        guard !сомнительные.isEmpty else { return т("aim_check_s") }
        return т("aim_check_s") + " " + String(format: т("aim_check_unsure"), сомнительные.joined(separator: ", "))
    }
}

/// Галочка-квадрат слева от подписи (у Toggle по умолчанию — переключатель справа).
struct ГалочкаИИФото: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(configuration.isOn ? Theme.зелёный2 : Theme.текстВторой)
                    .accessibilityHidden(true)
                configuration.label
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? [.isButton, .isSelected] : .isButton)
    }
}
