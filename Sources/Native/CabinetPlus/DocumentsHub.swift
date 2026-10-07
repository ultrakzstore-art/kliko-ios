import SwiftUI
import UIKit

/**
 «СЧЕТА И ДОКУМЕНТЫ» ОДНИМ ЭКРАНОМ (владелец: «раздел Счета и документы упростить + удалить и корзина очистить»).

 Раньше строка профиля открывала группу из трёх экранов («Компания и витрина», «Счета и заказы», «Журнал счетов»), а
 документы лежали в четырёх списках подряд. Теперь — один список всех документов, как вкладка «Документы» кабинета сайта
 (cabinet.php → #cmp-pane-docs, js/cabinet-business.js: b2bLoadOrders, invLoad):
   · счета B2B, выставленные мной (b2b_orders_list → as_seller) и мне поставщиками (as_buyer) — с теми же кнопками,
     что _b2bRow сайта: следующий шаг продавца (Подтвердить → Оплата пришла → Отгрузить / Завершить), «Отменить» с
     вопросом сайта, и документы заказа своим PDF (счёт, накладная, акт, договор — CabinetPlus/BusinessDocs.swift);
   · полученные документы (invoice_list role=buyer): счёт, акт, накладная, договор, доверенность, прайс-лист — нажатие
     открывает свой PDF, как invPrint сайта.
 Сверху — сегменты «Все · Счета · Акты · Договоры» (только виды, что есть в списке) и поиск по номеру, контрагенту и
 виду. Сначала «Актуальные» (ждут оплаты, подтверждения или моего шага), ниже свёрнутая группа «Неактуальные»
 (оплаченные и закрытые, отменённые, просроченные, полученные больше 30 дней назад); внутри групп — новые сверху.
 Остальное, что было разбросано по группе, — меню «+» в шапке: реквизиты компании, журнал счетов, коммерческие
 предложения, печать и подпись, «Выставить счёт» (на сайте: своей формы invoice_send в приложении нет).

 «УДАЛИТЬ» И «КОРЗИНА». У сайта удаления документов нет и быть не может: счёт, акт и договор — общий документ двух
 сторон, журнал счетов держит нумерацию без дыр. Поэтому «Удалить» здесь — убрать из СВОЕГО списка (правка сервера 109,
 inc/cabinet/doc_hide.php): документ остаётся в базе, у второй стороны, в журнале, в налогах. Удалённое — в «Корзине»
 (строка внизу списка): «Восстановить», «Удалить навсегда» и «Очистить корзину» (спрятать окончательно, тоже только из
 своего списка). Свой счёт продавца в работе (новый, ждёт оплату, оплачен, отгружен) убрать нельзя — сначала завершить
 или отменить; так же отвечает и сервер. Нет правки 109 на сервере (doc_hidden_list не отвечает JSON) — ни свайпа, ни
 корзины: список как у сайта.
 */

// MARK: - Тексты

enum СчетаДокументыText {
    static func т(_ ключ: String) -> String {
        let словарь = тексты[БизнесText.язык] ?? ru
        if let текст = словарь[ключ] ?? ru[ключ] { return текст }
        return БизнесРазделыText.т(ключ)
    }

    private static let тексты: [String: [String: String]] = ["ru": ru, "kk": kk, "en": en, "ar": ar]

    private static let ru: [String: String] = [
        "hub_seg_all": "Все", "hub_seg_inv": "Счета", "hub_seg_act": "Акты", "hub_seg_contract": "Договоры",
        "hub_search": "Номер или название", "hub_actual": "Актуальные", "hub_old": "Неактуальные",
        "hub_empty": "Документов пока нет",
        "hub_empty_s": "Здесь будут счета, акты и договоры — выставленные вами и полученные от поставщиков.",
        "hub_nothing": "Ничего не найдено", "hub_overdue": "просрочен", "hub_received": "получен",
        "hub_out": "Исходящий", "hub_in": "Входящий", "hub_more": "Создать и настроить",
        "hub_issue_site": "Выставить счёт (на сайте)", "hub_order_docs": "Документы счёта",
        "hub_trash": "Корзина", "hub_trash_empty": "Корзина пуста",
        "hub_trash_note": "Удалённые документы убраны только из вашего списка: у второй стороны, в журнале счетов и в отчётности они остаются.",
        "hub_del": "Удалить", "hub_del_q": "Убрать документ в корзину?",
        "hub_del_s": "Он останется у второй стороны, в журнале счетов и в отчётности — исчезнет только из вашего списка. Вернуть можно из «Корзины».",
        "hub_del_done": "Убрано в корзину", "hub_restore": "Восстановить", "hub_restored": "Восстановлено ✓",
        "hub_purge": "Удалить навсегда", "hub_purge_one_q": "Удалить документ навсегда?",
        "hub_purge_q": "Удалить навсегда %ld документов?",
        "hub_purge_s": "Из вашего списка документ пропадёт совсем, вернуть его будет нельзя. У второй стороны и в журнале счетов он останется.",
        "hub_purge_done": "Удалено навсегда", "hub_trash_clear": "Очистить корзину",
        "hub_in_progress": "Счёт в работе — сначала завершите или отмените его",
        "hub_not_found": "Документ не найден"
    ]

    private static let kk: [String: String] = [
        "hub_seg_all": "Барлығы", "hub_seg_inv": "Шоттар", "hub_seg_act": "Актілер", "hub_seg_contract": "Шарттар",
        "hub_search": "Нөмірі немесе атауы", "hub_actual": "Өзекті", "hub_old": "Өзекті емес",
        "hub_empty": "Әзірге құжаттар жоқ",
        "hub_empty_s": "Мұнда сіз жазған және жеткізушілерден алынған шоттар, актілер мен шарттар болады.",
        "hub_nothing": "Ештеңе табылмады", "hub_overdue": "мерзімі өтті", "hub_received": "алынды",
        "hub_out": "Шығыс", "hub_in": "Кіріс", "hub_more": "Жасау және баптау",
        "hub_issue_site": "Шот жазу (сайтта)", "hub_order_docs": "Шот құжаттары",
        "hub_trash": "Себет", "hub_trash_empty": "Себет бос",
        "hub_trash_note": "Жойылған құжаттар тек сіздің тізіміңізден алынды: екінші тарапта, шоттар журналында және есептілікте олар қалады.",
        "hub_del": "Жою", "hub_del_q": "Құжатты себетке салу керек пе?",
        "hub_del_s": "Ол екінші тарапта, шоттар журналында және есептілікте қалады — тек сіздің тізіміңізден жоғалады. «Себеттен» қайтаруға болады.",
        "hub_del_done": "Себетке салынды", "hub_restore": "Қалпына келтіру", "hub_restored": "Қалпына келтірілді ✓",
        "hub_purge": "Біржола жою", "hub_purge_one_q": "Құжатты біржола жою керек пе?",
        "hub_purge_q": "%ld құжатты біржола жою керек пе?",
        "hub_purge_s": "Құжат сіздің тізіміңізден мүлде жоғалады, оны қайтару мүмкін болмайды. Екінші тарапта және шоттар журналында ол қалады.",
        "hub_purge_done": "Біржола жойылды", "hub_trash_clear": "Себетті тазалау",
        "hub_in_progress": "Шот жұмыста — алдымен оны аяқтаңыз немесе болдырмаңыз",
        "hub_not_found": "Құжат табылмады"
    ]

    private static let en: [String: String] = [
        "hub_seg_all": "All", "hub_seg_inv": "Invoices", "hub_seg_act": "Acts", "hub_seg_contract": "Contracts",
        "hub_search": "Number or name", "hub_actual": "Current", "hub_old": "Not current",
        "hub_empty": "No documents yet",
        "hub_empty_s": "Invoices, acts and contracts you issue or receive from suppliers will appear here.",
        "hub_nothing": "Nothing found", "hub_overdue": "overdue", "hub_received": "received",
        "hub_out": "Outgoing", "hub_in": "Incoming", "hub_more": "Create and set up",
        "hub_issue_site": "Issue an invoice (on the website)", "hub_order_docs": "Invoice documents",
        "hub_trash": "Trash", "hub_trash_empty": "Trash is empty",
        "hub_trash_note": "Deleted documents are removed only from your list: the other party, the invoice journal and your reports keep them.",
        "hub_del": "Delete", "hub_del_q": "Move the document to trash?",
        "hub_del_s": "The other party, the invoice journal and your reports keep it — it disappears only from your list. You can restore it from Trash.",
        "hub_del_done": "Moved to trash", "hub_restore": "Restore", "hub_restored": "Restored ✓",
        "hub_purge": "Delete forever", "hub_purge_one_q": "Delete the document forever?",
        "hub_purge_q": "Delete %ld documents forever?",
        "hub_purge_s": "The document will disappear from your list for good and can't be brought back. The other party and the invoice journal keep it.",
        "hub_purge_done": "Deleted forever", "hub_trash_clear": "Empty trash",
        "hub_in_progress": "This invoice is in progress — complete or cancel it first",
        "hub_not_found": "Document not found"
    ]

    private static let ar: [String: String] = [
        "hub_seg_all": "الكل", "hub_seg_inv": "الفواتير", "hub_seg_act": "المحاضر", "hub_seg_contract": "العقود",
        "hub_search": "الرقم أو الاسم", "hub_actual": "الحالية", "hub_old": "غير الحالية",
        "hub_empty": "لا توجد مستندات بعد",
        "hub_empty_s": "ستظهر هنا الفواتير والمحاضر والعقود التي تصدرها أو تتلقاها من الموردين.",
        "hub_nothing": "لم يتم العثور على شيء", "hub_overdue": "متأخرة", "hub_received": "مستلمة",
        "hub_out": "صادرة", "hub_in": "واردة", "hub_more": "إنشاء وإعداد",
        "hub_issue_site": "إصدار فاتورة (على الموقع)", "hub_order_docs": "مستندات الفاتورة",
        "hub_trash": "سلة المحذوفات", "hub_trash_empty": "السلة فارغة",
        "hub_trash_note": "المستندات المحذوفة أُزيلت من قائمتك فقط: تبقى لدى الطرف الآخر وفي سجل الفواتير وفي التقارير.",
        "hub_del": "حذف", "hub_del_q": "نقل المستند إلى السلة؟",
        "hub_del_s": "يبقى لدى الطرف الآخر وفي سجل الفواتير وفي التقارير — يختفي من قائمتك فقط. يمكن استعادته من السلة.",
        "hub_del_done": "نُقل إلى السلة", "hub_restore": "استعادة", "hub_restored": "تمت الاستعادة ✓",
        "hub_purge": "حذف نهائي", "hub_purge_one_q": "حذف المستند نهائيًا؟",
        "hub_purge_q": "حذف %ld من المستندات نهائيًا؟",
        "hub_purge_s": "سيختفي المستند من قائمتك نهائيًا ولا يمكن إرجاعه. يبقى لدى الطرف الآخر وفي سجل الفواتير.",
        "hub_purge_done": "تم الحذف نهائيًا", "hub_trash_clear": "إفراغ السلة",
        "hub_in_progress": "الفاتورة قيد التنفيذ — أكملها أو ألغها أولًا",
        "hub_not_found": "المستند غير موجود"
    ]
}

private func тД(_ ключ: String) -> String { СчетаДокументыText.т(ключ) }

// MARK: - Корзина на сервере (правка 109)

@MainActor
enum КорзинаДокументовAPI {
    typealias A = МоиОбъявленияAPI

    /// Корзина (ключ → когда) и спрятанные навсегда.
    struct Состояние: Equatable {
        var корзина: [String: String] = [:]
        var спрятаны: Set<String> = []
    }

    private static func разобрать(_ j: [String: Any]) -> Состояние {
        var итог = Состояние()
        if let к = j["trash"] as? [String: Any] {
            for (ключ, когда) in к { итог.корзина[ключ] = A.строка(когда) }
        }
        let спрятаны: [Any] = (j["gone"] as? [Any]) ?? []
        итог.спрятаны = Set(спрятаны.map { A.строка($0) })
        return итог
    }

    /// doc_hidden_list {csrf}. nil — на сервере нет правки 109 (или нет связи): корзины в приложении нет.
    static func список() async -> Состояние? {
        guard let j = try? await A.отправить("cabinet.php?action=doc_hidden_list", тело: [:]), A.да(j["ok"]) else {
            return nil
        }
        return разобрать(j)
    }

    /// doc_hide {csrf, keys, op: hide | restore | purge} → новое состояние или текст ошибки.
    static func изменить(_ ключи: [String], оп: String) async -> Result<Состояние, СбойКорзины> {
        do {
            let j = try await A.отправить("cabinet.php?action=doc_hide", тело: ["keys": ключи, "op": оп])
            if A.да(j["ok"]) { return .success(разобрать(j)) }
            switch A.строка(j["error"]) {
            case "in_progress": return .failure(СбойКорзины(текст: тД("hub_in_progress")))
            case "not_found": return .failure(СбойКорзины(текст: тД("hub_not_found")))
            case "auth": return .failure(СбойКорзины(текст: CabinetText.т("signed_out")))
            default: return .failure(СбойКорзины(текст: БизнесText.т("err_generic")))
            }
        } catch {
            return .failure(СбойКорзины(текст: БизнесText.т("no_conn")))
        }
    }
}

struct СбойКорзины: Error {
    let текст: String
}

// MARK: - Документ списка

/// Одна строка единого списка: счёт B2B (свой или поставщика) или полученный документ.
struct ДокументСписка: Identifiable {
    enum Вид: String {
        case счёт = "invoice"
        case акт = "act"
        case договор = "contract"
        case накладная = "waybill"
        case доверенность = "poa"
        case прайс = "pricelist"

        var название: String { БизнесРазделыText.т("doc_t_" + rawValue) }

        var значок: String {
            switch self {
            case .счёт: return "doc.text"
            case .акт: return "checkmark.seal"
            case .договор: return "signature"
            case .накладная: return "shippingbox"
            case .доверенность: return "person.text.rectangle"
            case .прайс: return "list.bullet.rectangle"
            }
        }
    }

    enum Тон {
        case ждёт, хорошо, плохо, инфо
    }

    /// Ключ корзины: "o:<id заказа>", "i:<id документа>"; у документа без id — "n:<порядок>" (убрать нельзя).
    let id: String
    let вид: Вид
    let заказ: ЗаказB2B?
    let полученный: ПолученныйДокумент?
    let контрагент: String
    let номер: String
    let когда: Date?
    let датаТекст: String
    let сумма: Int?
    let статус: String
    let тон: Тон
    let актуален: Bool
    /// Выставлен мной (я продавец).
    let исходящий: Bool
    /// «Оплатить до» (valid_until) — у счёта, что ждёт оплаты; иначе пусто.
    let срокТекст: String

    /// Можно убрать в корзину: есть ключ сервера и это не мой счёт в работе.
    var можноУбрать: Bool {
        guard !id.hasPrefix("n:") else { return false }
        return !вРаботе
    }

    /// Свой счёт продавца, по которому ждут шага: убрать нельзя (так же отвечает сервер — in_progress).
    var вРаботе: Bool {
        guard let заказ, заказ.продаю else { return false }
        return ["new", "confirmed", "paid", "shipped"].contains(заказ.статус)
    }

    /// «Счёт № 12» · «Прайс-лист».
    var заголовок: String {
        if вид == .прайс || номер.isEmpty { return вид.название }
        return вид.название + " № " + номер
    }

    /// Строка для поиска: номер, контрагент, вид, сумма.
    var стог: String {
        [номер, контрагент, вид.название, заголовок, сумма.map { String($0) } ?? ""].joined(separator: " ").lowercased()
    }

    // MARK: Разбор

    private static let iso: ISO8601DateFormatter = ISO8601DateFormatter()

    private static func датаISO(_ строка: String) -> Date? {
        guard !строка.isEmpty else { return nil }
        if let д = iso.date(from: строка) { return д }
        let ф = DateFormatter()
        ф.locale = Locale(identifier: "en_US_POSIX")
        for шаблон in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"] {
            ф.dateFormat = шаблон
            if let д = ф.date(from: строка) { return д }
        }
        return nil
    }

    private static func датаСайта(_ строка: String) -> Date? {
        let ф = DateFormatter()
        ф.locale = Locale(identifier: "en_US_POSIX")
        ф.dateFormat = "dd.MM.yyyy"
        return ф.date(from: строка)
    }

    static func показ(_ д: Date?) -> String {
        guard let д else { return "" }
        let ф = DateFormatter()
        ф.locale = Locale(identifier: "en_US_POSIX")
        ф.dateFormat = "dd.MM.yyyy"
        return ф.string(from: д)
    }

    /// Счёт B2B: статус и актуальность. Просрочен — новый или «ждём оплату» после valid_until.
    init(заказ з: ЗаказB2B, сейчас: Date) {
        id = "o:" + з.id
        вид = .счёт
        заказ = з
        полученный = nil
        контрагент = з.контрагент.isEmpty
            ? БизнесРазделыText.т(з.продаю ? "b2b_buyer_word" : "b2b_supplier") : з.контрагент
        номер = з.номер
        когда = Self.датаISO(МоиОбъявленияAPI.строка(з.сырое["created_at"]))
        датаТекст = Self.показ(когда)
        сумма = з.сумма
        исходящий = з.продаю
        let срок = Self.датаISO(з.до)
        срокТекст = (з.статус == "new" || з.статус == "confirmed") ? Self.показ(срок) : ""
        let просрочен = (з.статус == "new" || з.статус == "confirmed") && (срок.map { $0 < сейчас } ?? false)
        if просрочен {
            статус = тД("hub_overdue")
            тон = .плохо
            актуален = false
            return
        }
        switch з.статус {
        case "new", "confirmed", "paid", "shipped", "done", "cancelled":
            статус = БизнесРазделыText.т("b2b_st_" + з.статус)
        default:
            статус = з.статус
        }
        switch з.статус {
        case "cancelled":
            тон = .плохо
            актуален = false
        case "done":
            тон = .хорошо
            актуален = false
        case "paid", "shipped":
            тон = .инфо
            /* Продавцу ещё отгрузить или завершить — его шаг; покупателю — уже оплачено. */
            актуален = з.продаю
        default:
            тон = .ждёт
            актуален = true
        }
    }

    /// Полученный документ (invoice_list): статуса у сервера нет — актуален 30 дней с даты.
    init(полученный п: ПолученныйДокумент, сейчас: Date) {
        id = п.ключ.isEmpty ? "n:" + String(п.id) : "i:" + п.ключ
        вид = Вид(rawValue: п.вид) ?? .счёт
        заказ = nil
        полученный = п
        контрагент = п.продавец.isEmpty ? "—" : п.продавец
        номер = п.номер
        когда = Self.датаISO(п.создан) ?? Self.датаСайта(п.дата)
        датаТекст = п.дата.isEmpty ? Self.показ(когда) : п.дата
        сумма = вид == .прайс ? nil : п.сумма
        исходящий = false
        срокТекст = ""
        статус = тД("hub_received")
        тон = .инфо
        if let когда {
            актуален = сейчас.timeIntervalSince(когда) < 30 * 86_400
        } else {
            актуален = true
        }
    }
}

// MARK: - Модель экрана

@MainActor
final class СчетаДокументыМодель: ObservableObject {
    enum Сегмент: String, CaseIterable, Identifiable {
        case все, счета, акты, договоры
        var id: String { rawValue }

        var название: String {
            switch self {
            case .все: return тД("hub_seg_all")
            case .счета: return тД("hub_seg_inv")
            case .акты: return тД("hub_seg_act")
            case .договоры: return тД("hub_seg_contract")
            }
        }

        var вид: ДокументСписка.Вид? {
            switch self {
            case .все: return nil
            case .счета: return .счёт
            case .акты: return .акт
            case .договоры: return .договор
            }
        }
    }

    @Published private(set) var состояние: СостояниеРаздела = .идёт
    @Published private(set) var документы: [ДокументСписка] = []
    /// nil — на сервере нет корзины (правка 109): ни свайпа «Удалить», ни строки «Корзина».
    @Published private(set) var корзина: КорзинаДокументовAPI.Состояние? = nil
    @Published var сегмент: Сегмент = .все
    @Published var поиск: String = ""
    @Published var старыеОткрыты = false
    @Published private(set) var занят: String? = nil
    @Published private(set) var плашка: String? = nil

    private var полученные: [ПолученныйДокумент] = []

    // MARK: Загрузка

    func загрузить() async {
        let бизнес = БизнесМодель.shared
        if документы.isEmpty { состояние = .идёт }
        await бизнес.загрузитьСтраницу()
        if бизнес.загрузка == .нуженВход {
            состояние = .нуженВход
            return
        }
        await бизнес.загрузитьЗаказы()
        var ошибка: String? = nil
        do {
            полученные = try await БизнесРазделыAPI.полученныеСчета()
        } catch let с as БизнесРазделыAPI.Сбой {
            if с.нуженВход {
                состояние = .нуженВход
                return
            }
            ошибка = с.текст
        } catch {
            ошибка = БизнесText.т("no_conn")
        }
        корзина = await КорзинаДокументовAPI.список()
        собрать()
        if let ошибка, бизнес.заказыПродаю == nil && бизнес.заказыПокупаю == nil {
            состояние = .ошибка(ошибка)
        } else {
            состояние = .готово
        }
    }

    private func собрать() {
        let бизнес = БизнесМодель.shared
        let сейчас = Date()
        var итог: [ДокументСписка] = []
        for з in (бизнес.заказыПродаю ?? []) + (бизнес.заказыПокупаю ?? []) {
            итог.append(ДокументСписка(заказ: з, сейчас: сейчас))
        }
        for п in полученные {
            итог.append(ДокументСписка(полученный: п, сейчас: сейчас))
        }
        документы = итог
        if let в = сегмент.вид, !итог.contains(where: { $0.вид == в }) { сегмент = .все }
    }

    // MARK: Отбор

    /// Сегменты над списком: «Все» и только те виды, что есть.
    var сегменты: [Сегмент] {
        let есть = Set(вСписке.map { $0.вид })
        return Сегмент.allCases.filter { с in
            guard let в = с.вид else { return true }
            return есть.contains(в)
        }
    }

    /// Не в корзине и не спрятаны навсегда.
    private var вСписке: [ДокументСписка] {
        guard let корзина else { return документы }
        return документы.filter { корзина.корзина[$0.id] == nil && !корзина.спрятаны.contains($0.id) }
    }

    private func новыеСверху(_ список: [ДокументСписка]) -> [ДокументСписка] {
        список.sorted { (a, b) in (a.когда ?? .distantPast) > (b.когда ?? .distantPast) }
    }

    private var отобранные: [ДокументСписка] {
        let запрос = поиск.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return вСписке.filter { д in
            if let в = сегмент.вид, д.вид != в { return false }
            if !запрос.isEmpty && !д.стог.contains(запрос) { return false }
            return true
        }
    }

    var актуальные: [ДокументСписка] { новыеСверху(отобранные.filter { $0.актуален }) }
    var неактуальные: [ДокументСписка] { новыеСверху(отобранные.filter { !$0.актуален }) }
    var списокПуст: Bool { вСписке.isEmpty }

    /// Корзина: убранные документы, что есть в загруженных списках, — недавно убранные сверху.
    var вКорзине: [ДокументСписка] {
        guard let корзина else { return [] }
        return документы.filter { корзина.корзина[$0.id] != nil }
            .sorted { (корзина.корзина[$0.id] ?? "") > (корзина.корзина[$1.id] ?? "") }
    }

    // MARK: Корзина

    func убрать(_ д: ДокументСписка) async {
        await корзинаИзменить([д.id], оп: "hide", готово: тД("hub_del_done"))
    }

    func восстановить(_ д: ДокументСписка) async {
        await корзинаИзменить([д.id], оп: "restore", готово: тД("hub_restored"))
    }

    func удалитьНавсегда(_ д: ДокументСписка) async {
        await корзинаИзменить([д.id], оп: "purge", готово: тД("hub_purge_done"))
    }

    /// «Очистить корзину» — все ключи корзины, и те, чьих документов в списках уже нет.
    func очистить() async {
        guard let корзина, !корзина.корзина.isEmpty else { return }
        await корзинаИзменить(Array(корзина.корзина.keys), оп: "purge", готово: тД("hub_purge_done"))
    }

    private func корзинаИзменить(_ ключи: [String], оп: String, готово: String) async {
        guard занят == nil, !ключи.isEmpty else { return }
        занят = ключи.count == 1 ? ключи[0] : "*"
        let итог = await КорзинаДокументовAPI.изменить(ключи, оп: оп)
        занят = nil
        switch итог {
        case .success(let новое):
            withAnimation { корзина = новое }
            показать(готово)
        case .failure(let сбой):
            показать(сбой.текст)
        }
    }

    // MARK: Заказ B2B

    /// b2bStatus: запись → «Статус обновлён» и счета заново.
    func сменить(_ заказ: ЗаказB2B, _ статус: String) async {
        guard занят == nil else { return }
        занят = "o:" + заказ.id
        let ошибка = await БизнесРазделыAPI.статусЗаказа(заказ.id, статус)
        занят = nil
        показать(ошибка ?? БизнесРазделыText.т("b2b_status_updated"))
        if ошибка == nil {
            await БизнесМодель.shared.загрузитьЗаказы()
            собрать()
        }
    }

    func показать(_ текст: String) {
        withAnimation { плашка = текст }
        UIAccessibility.post(notification: .announcement, argument: текст)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            guard let self, self.плашка == текст else { return }
            withAnimation { self.плашка = nil }
        }
    }
}

// MARK: - Открыть документ

@MainActor
enum ОткрытьДокументСписка {
    /// Нажатие на строку: счёт заказа (или другой документ заказа) / полученный документ — своим PDF.
    static func показать(_ д: ДокументСписка, вид: String = "invoice", часть: String? = nil) {
        if let заказ = д.заказ {
            var данные = ДанныеДокумента(заказ: заказ.сырое, часть: часть)
            данные.вид = вид
            ОкнаДокументов.показать(ДокументКабинета(заголовок: ДокументыБизнеса.заголовок(данные),
                                                     источник: .разметка(ДокументыБизнеса.разметка(данные))))
        } else if let п = д.полученный {
            ОкнаДокументов.показать(ДокументКабинета(заголовок: ДокументыБизнеса.заголовок(п.данные),
                                                     источник: .разметка(ДокументыБизнеса.разметка(п.данные))))
        }
    }
}

// MARK: - Экран

/// Переходы меню «+» шапки.
enum ПереходДокументов: String, Hashable, Identifiable {
    case компания, журнал, кп, печать, корзина
    var id: String { rawValue }
}

struct ЭкранСчетовИДокументов: View {
    let открыть: (URL) -> Void

    @StateObject private var модель = СчетаДокументыМодель()
    @State private var переход: ПереходДокументов? = nil
    @State private var убрать: ДокументСписка? = nil
    @State private var отменить: ЗаказB2B? = nil

    init(открыть: @escaping (URL) -> Void) {
        self.открыть = открыть
    }

    var body: some View {
        РамкаРаздела(состояние: модель.состояние, открыть: открыть, повторить: { Task { await модель.загрузить() } }) {
            список
        }
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .navigationTitle(CabinetText.т("docs"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { меню }
        }
        .task { await модель.загрузить() }
        .navigationDestination(item: $переход) { куда in
            switch куда {
            case .компания: ЭкранКомпании(открыть: открыть)
            case .журнал: ЭкранЖурнала(открыть: открыть)
            case .кп: ЭкранКП(открыть: открыть)
            case .печать: ЭкранПечатиИПодписи(открыть: открыть)
            case .корзина: ЭкранКорзиныДокументов(модель: модель)
            }
        }
        .confirmationDialog(тД("hub_del_q"), isPresented: вопросУбрать, titleVisibility: .visible,
                            presenting: убрать) { д in
            Button(тД("hub_del"), role: .destructive) { Task { await модель.убрать(д) } }
            Button(БизнесРазделыText.т("b2b_cancel_no"), role: .cancel) {}
        } message: { _ in
            Text(тД("hub_del_s"))
        }
        .alert(заголовокОтмены, isPresented: вопросОтменить, presenting: отменить) { заказ in
            Button(БизнесРазделыText.т("b2b_cancel_yes"), role: .destructive) {
                Task { await модель.сменить(заказ, "cancelled") }
            }
            Button(БизнесРазделыText.т("b2b_cancel_no"), role: .cancel) {}
        } message: { _ in
            Text(БизнесРазделыText.т("b2b_cancel_h"))
        }
        .overlay(alignment: .bottom) {
            if let текст = модель.плашка { ПлашкаКошелька(текст: текст) }
        }
    }

    private var вопросУбрать: Binding<Bool> {
        Binding(get: { убрать != nil }, set: { if !$0 { убрать = nil } })
    }

    private var вопросОтменить: Binding<Bool> {
        Binding(get: { отменить != nil }, set: { if !$0 { отменить = nil } })
    }

    /// «Отменить счёт №12?»
    private var заголовокОтмены: String {
        guard let заказ = отменить else { return "" }
        let номер = заказ.номер.isEmpty ? "" : " №\(заказ.номер)"
        return "\(БизнесРазделыText.т("b2b_cancel_q"))\(номер)?"
    }

    /// «+» шапки: всё, что раньше было отдельными строками группы.
    private var меню: some View {
        Menu {
            Button { переход = .компания } label: {
                Label(БизнесText.т("cmp_card_t"), systemImage: "building.2")
            }
            Button { переход = .печать } label: {
                Label(БизнесText.т("biz_seal"), systemImage: "signature")
            }
            Button { переход = .журнал } label: {
                Label(БизнесРазделыText.т("jrn_title"), systemImage: "list.number")
            }
            Button { переход = .кп } label: {
                Label(БизнесText.т("biz_kp"), systemImage: "doc.richtext")
            }
            Button {
                if let u = Config.страницаСайта("cabinet.php?s=company") { открыть(u) }
            } label: {
                Label(тД("hub_issue_site"), systemImage: "arrow.up.right.square")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.акцент)
        }
        .accessibilityLabel(тД("hub_more"))
    }

    private var список: some View {
        List {
            Section {
                if модель.сегменты.count > 1 {
                    Picker(тД("hub_seg_all"), selection: $модель.сегмент) {
                        ForEach(модель.сегменты) { с in
                            Text(с.название).tag(с)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
            }
            if модель.списокПуст {
                Section {
                    пусто(тД("hub_empty"), подпись: тД("hub_empty_s"))
                }
            } else if модель.актуальные.isEmpty && модель.неактуальные.isEmpty {
                Section {
                    пусто(тД("hub_nothing"), подпись: nil)
                }
            }
            if !модель.актуальные.isEmpty {
                Section {
                    ForEach(модель.актуальные) { д in строка(д) }
                } header: {
                    Text(тД("hub_actual") + " · " + String(модель.актуальные.count))
                }
            }
            if !модель.неактуальные.isEmpty {
                Section {
                    кнопкаСтарых
                    if модель.старыеОткрыты {
                        ForEach(модель.неактуальные) { д in строка(д) }
                    }
                }
            }
            if модель.корзина != nil {
                Section {
                    строкаКорзины
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .searchable(text: $модель.поиск, placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: тД("hub_search"))
        .refreshable { await модель.загрузить() }
    }

    private func пусто(_ заголовок: String, подпись: String?) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 30))
                .foregroundStyle(Theme.текстВторой)
                .accessibilityHidden(true)
            Text(заголовок)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.текст)
            if let подпись {
                Text(подпись)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    /// «Неактуальные · N» — свёрнуты по умолчанию.
    private var кнопкаСтарых: some View {
        Button {
            withAnimation { модель.старыеОткрыты.toggle() }
        } label: {
            HStack {
                Text(тД("hub_old") + " · " + String(модель.неактуальные.count))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                Spacer(minLength: 8)
                Image(systemName: модель.старыеОткрыты ? "chevron.up" : "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.текстВторой)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(модель.старыеОткрыты ? .isSelected : [])
    }

    private var строкаКорзины: some View {
        Button {
            переход = .корзина
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "trash")
                    .foregroundStyle(Theme.текстВторой)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                Text(тД("hub_trash"))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.текст)
                Spacer(minLength: 8)
                if !модель.вКорзине.isEmpty {
                    Text(String(модель.вКорзине.count))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.текстВторой)
                }
                СтрелкаСтрокиКабинета()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func строка(_ д: ДокументСписка) -> some View {
        СтрокаДокументаСписка(документ: д, занят: модель.занят == д.id, шаг: { статус in
            guard let заказ = д.заказ else { return }
            Task { await модель.сменить(заказ, статус) }
        })
        .contentShape(Rectangle())
        .onTapGesture { ОткрытьДокументСписка.показать(д) }
        .accessibilityAction { ОткрытьДокументСписка.показать(д) }
        .contextMenu { менюСтроки(д) }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if модель.корзина != nil && д.можноУбрать {
                Button(role: .destructive) {
                    убрать = д
                } label: {
                    Label(тД("hub_del"), systemImage: "trash")
                }
            }
        }
    }

    /// Долгое нажатие: документы заказа, шаг продавца, «Отменить», «Удалить».
    @ViewBuilder
    private func менюСтроки(_ д: ДокументСписка) -> some View {
        if let заказ = д.заказ {
            Section(тД("hub_order_docs")) {
                Button { ОткрытьДокументСписка.показать(д) } label: {
                    Label(КабинетПлюсText.т("doc_invoice"), systemImage: "doc.text")
                }
                if заказ.вид != "services" {
                    Button { ОткрытьДокументСписка.показать(д, вид: "waybill", часть: "goods") } label: {
                        Label(КабинетПлюсText.т("doc_waybill"), systemImage: "shippingbox")
                    }
                }
                if заказ.вид != "goods" {
                    Button { ОткрытьДокументСписка.показать(д, вид: "act", часть: "services") } label: {
                        Label(КабинетПлюсText.т("doc_act"), systemImage: "checkmark.seal")
                    }
                }
                Button { ОткрытьДокументСписка.показать(д, вид: "contract") } label: {
                    Label(КабинетПлюсText.т("doc_contract"), systemImage: "signature")
                }
            }
            if let шаг = СтрокаДокументаСписка.следующийШаг(заказ) {
                Button { Task { await модель.сменить(заказ, шаг.0) } } label: {
                    Label(шаг.1, systemImage: "arrow.right.circle")
                }
            }
            if заказ.гость && !заказ.телефон.isEmpty,
               let тел = URL(string: "tel:" + заказ.телефон.filter { $0.isNumber || $0 == "+" }) {
                Link(destination: тел) {
                    Label(заказ.телефон, systemImage: "phone")
                }
            }
            if заказ.гость && !заказ.почта.isEmpty, let почта = URL(string: "mailto:" + заказ.почта) {
                Link(destination: почта) {
                    Label(заказ.почта, systemImage: "envelope")
                }
            }
            if заказ.статус == "new" || заказ.статус == "confirmed" {
                Button(role: .destructive) { отменить = заказ } label: {
                    Label(БизнесРазделыText.т("b2b_cancel"), systemImage: "xmark.circle")
                }
            }
        } else {
            Button { ОткрытьДокументСписка.показать(д) } label: {
                Label(д.заголовок, systemImage: д.вид.значок)
            }
        }
        if модель.корзина != nil && д.можноУбрать {
            Button(role: .destructive) { убрать = д } label: {
                Label(тД("hub_del"), systemImage: "trash")
            }
        }
    }
}

// MARK: - Строка

struct СтрокаДокументаСписка: View {
    let документ: ДокументСписка
    let занят: Bool
    let шаг: (String) -> Void

    /// Следующий шаг продавца (_b2bRow): new → confirmed → paid → shipped (товары) / done (услуги), shipped → done.
    static func следующийШаг(_ заказ: ЗаказB2B) -> (String, String)? {
        guard заказ.продаю else { return nil }
        switch заказ.статус {
        case "new": return ("confirmed", БизнесРазделыText.т("b2b_confirm"))
        case "confirmed": return ("paid", БизнесРазделыText.т("b2b_mark_paid"))
        case "paid":
            return заказ.вид != "services" ? ("shipped", БизнесРазделыText.т("b2b_ship"))
                : ("done", БизнесРазделыText.т("b2b_finish"))
        case "shipped": return ("done", БизнесРазделыText.т("b2b_finish"))
        default: return nil
        }
    }

    /// Первые три позиции «название × кол-во» и «+N» (у счёта B2B).
    private var позиции: String {
        guard let заказ = документ.заказ, !заказ.позиции.isEmpty else { return "" }
        var текст = заказ.позиции.prefix(3).map { $0.0 + " × " + String($0.1) }.joined(separator: ", ")
        if заказ.позиции.count > 3 { текст += " +" + String(заказ.позиции.count - 3) }
        return текст
    }

    private var краска: Color {
        switch документ.тон {
        case .ждёт: return КраскаОбъявлений.предупреждениеТекст
        case .хорошо: return КраскаОбъявлений.хорошоТекст
        case .плохо: return КраскаОбъявлений.плохоТекст
        case .инфо: return КраскаОбъявлений.инфоТекст
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: документ.вид.значок)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(документ.актуален ? Theme.акцент : Theme.текстВторой)
                .frame(width: 34, height: 34)
                .background(Theme.оттенокАкцента.opacity(документ.актуален ? 1 : 0.4),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(документ.заголовок)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.текст)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    if let сумма = документ.сумма {
                        Text(СделкиФормат.тенге(сумма))
                            .font(.system(size: 14.5, weight: .heavy))
                            .foregroundStyle(документ.тон == .плохо ? Theme.текстВторой : Theme.текст)
                            .strikethrough(документ.заказ?.статус == "cancelled")
                            .monospacedDigit()
                    }
                }
                HStack(spacing: 6) {
                    Text(документ.контрагент)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.текст)
                        .lineLimit(1)
                    if документ.заказ?.гость == true {
                        МеткаБизнеса(текст: БизнесРазделыText.т("b2b_guest_tag"))
                    }
                }
                if !позиции.isEmpty {
                    Text(позиции)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.текстВторой)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    Text(документ.статус)
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(краска)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(краска.opacity(0.12), in: Capsule())
                    Text(документ.исходящий ? тД("hub_out") : тД("hub_in"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                    if !документ.срокТекст.isEmpty && документ.актуален {
                        Text(БизнесРазделыText.т("b2b_until") + " " + документ.срокТекст)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.текстВторой)
                    }
                    Spacer(minLength: 6)
                    Text(документ.датаТекст)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                        .monospacedDigit()
                }
                if let заказ = документ.заказ, документ.актуален, let ш = Self.следующийШаг(заказ) {
                    КнопкаБизнеса(подпись: ш.1, занято: занят) { шаг(ш.0) }
                        .padding(.top, 4)
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(документ.актуален ? 1 : 0.75)
        .accessibilityElement(children: .combine)
        .accessibilityHint(КабинетПлюсText.т("doc_open_hint"))
    }
}

// MARK: - Корзина

struct ЭкранКорзиныДокументов: View {
    @ObservedObject var модель: СчетаДокументыМодель

    @State private var навсегда: ДокументСписка? = nil
    @State private var очистить: Int? = nil

    var body: some View {
        List {
            Section {
                Text(тД("hub_trash_note"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if модель.вКорзине.isEmpty {
                Section {
                    Text(тД("hub_trash_empty"))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.текстВторой)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            } else {
                Section {
                    ForEach(модель.вКорзине) { д in строка(д) }
                }
                Section {
                    Button(role: .destructive) {
                        очистить = модель.корзина?.корзина.count ?? модель.вКорзине.count
                    } label: {
                        HStack {
                            if модель.занят == "*" { ProgressView() }
                            Label(тД("hub_trash_clear"), systemImage: "trash.slash")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(модель.занят != nil)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .navigationTitle(тД("hub_trash"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(тД("hub_purge_one_q"), isPresented: вопросНавсегда, titleVisibility: .visible,
                            presenting: навсегда) { д in
            Button(тД("hub_purge"), role: .destructive) { Task { await модель.удалитьНавсегда(д) } }
            Button(БизнесРазделыText.т("b2b_cancel_no"), role: .cancel) {}
        } message: { _ in
            Text(тД("hub_purge_s"))
        }
        .confirmationDialog(тД("hub_trash_clear"), isPresented: вопросОчистить, titleVisibility: .visible,
                            presenting: очистить) { _ in
            Button(тД("hub_purge"), role: .destructive) { Task { await модель.очистить() } }
            Button(БизнесРазделыText.т("b2b_cancel_no"), role: .cancel) {}
        } message: { число in
            Text(String(format: тД("hub_purge_q"), число) + "\n" + тД("hub_purge_s"))
        }
        .overlay(alignment: .bottom) {
            if let текст = модель.плашка { ПлашкаКошелька(текст: текст) }
        }
    }

    private var вопросНавсегда: Binding<Bool> {
        Binding(get: { навсегда != nil }, set: { if !$0 { навсегда = nil } })
    }

    private var вопросОчистить: Binding<Bool> {
        Binding(get: { очистить != nil }, set: { if !$0 { очистить = nil } })
    }

    private func строка(_ д: ДокументСписка) -> some View {
        СтрокаДокументаСписка(документ: д, занят: модель.занят == д.id, шаг: { _ in })
            .contentShape(Rectangle())
            .onTapGesture { ОткрытьДокументСписка.показать(д) }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    Task { await модель.восстановить(д) }
                } label: {
                    Label(тД("hub_restore"), systemImage: "arrow.uturn.backward")
                }
                .tint(Theme.акцент)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    навсегда = д
                } label: {
                    Label(тД("hub_purge"), systemImage: "trash.slash")
                }
            }
            .contextMenu {
                Button {
                    Task { await модель.восстановить(д) }
                } label: {
                    Label(тД("hub_restore"), systemImage: "arrow.uturn.backward")
                }
                Button(role: .destructive) {
                    навсегда = д
                } label: {
                    Label(тД("hub_purge"), systemImage: "trash.slash")
                }
            }
    }
}
