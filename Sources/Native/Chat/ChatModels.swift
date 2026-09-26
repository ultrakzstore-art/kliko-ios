import Foundation

/**
 МОДЕЛИ ЧАТА — ответы dm.php (этап 3 перехода на SwiftUI, 25.09.2026).

 Контракт — тот же, по которому в июле жил первый нативный чат (коммит 387e7ca): list → threads, open/poll/send →
 thread{id, messages}. Разбор терпимый, как у ленты (Listing): число вместо строки, пропавшее поле или новое поле не
 роняют весь диалог. Сообщение, которое не разобралось, пропускаем.
 */

/// Ключ-строка для терпимого разбора.
struct ЧатКлюч: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ s: String) { stringValue = s }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

extension KeyedDecodingContainer where K == ЧатКлюч {
    func строка(_ ключ: String) -> String? {
        let k = ЧатКлюч(ключ)
        if let s = try? decode(String.self, forKey: k) { return s }
        if let i = try? decode(Int.self, forKey: k) { return String(i) }
        if let d = try? decode(Double.self, forKey: k) { return String(Int(d)) }
        return nil
    }
    func целое(_ ключ: String) -> Int {
        let k = ЧатКлюч(ключ)
        if let i = try? decode(Int.self, forKey: k) { return i }
        if let s = try? decode(String.self, forKey: k), let i = Int(s) { return i }
        return 0
    }
    /// Этап 45: дробное число (рейтинг мастера в заявке, mrating) — число или строка; прочее — 0.
    func дробное(_ ключ: String) -> Double {
        let k = ЧатКлюч(ключ)
        if let d = try? decode(Double.self, forKey: k) { return d }
        if let s = try? decode(String.self, forKey: k), let d = Double(s) { return d }
        return 0
    }
    func да(_ ключ: String) -> Bool {
        let k = ЧатКлюч(ключ)
        if let b = try? decode(Bool.self, forKey: k) { return b }
        if let i = try? decode(Int.self, forKey: k) { return i != 0 }
        if let s = try? decode(String.self, forKey: k) { return s == "1" || s.lowercased() == "true" }
        return false
    }
}

/// Строка списка диалогов (dm.php?action=list).
struct ЧатДиалог: Identifiable, Hashable, Decodable {
    let id: String
    let собеседникID: String
    let собеседник: String
    let объявлениеID: String
    let объявление: String
    let обложка: String
    let последнее: String
    let последнееМоё: Bool
    /// Последнее — служебное уведомление («Покупатель отозвал своё предложение.»), а не слова человека.
    let последнееСистемное: Bool
    let последнееКогда: String
    let непрочитано: Int

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: ЧатКлюч.self)
        guard let tid = c.строка("tid") ?? c.строка("id"), !tid.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "нет tid"))
        }
        id = tid
        собеседникID = c.строка("peer_id") ?? ""
        собеседник = c.строка("peer_name") ?? ""
        объявлениеID = c.строка("listing_id") ?? ""
        объявление = c.строка("listing_title") ?? ""
        обложка = c.строка("listing_img") ?? ""
        непрочитано = c.целое("unread")
        if let last = try? c.nestedContainer(keyedBy: ЧатКлюч.self, forKey: ЧатКлюч("last")) {
            let типПоследнего = last.строка("type") ?? "text"
            let текстПоследнего = last.строка("text") ?? ""
            /* Владелец 25.09.2026, проверка на телефоне, сборка 33: в списке было «Вы: Покупатель отозвал своё
               предложение.» — сервер пишет уведомление от имени того, кто его вызвал (mine = true). У сайта это
               служебная строка без автора, поэтому «Вы: » у неё не ставим: последнееМоё — только у слов человека. */
            /* Этап 45: превью строки инбокса у сайта (_msgRowDm) проверяет только last.type === "system"; правило
               уведомлений — общее с перепиской (этоУведомление), с проверенными полями карты кабинета (§6.4.10). */
            let служебное = ЧатСообщение.этоУведомление(
                роль: last.строка("role") ?? "",
                вид: last.строка("kind") ?? "",
                тип: типПоследнего,
                текст: текстПоследнего)
            последнее = ЧатСообщение.подпись(тип: типПоследнего, текст: текстПоследнего)
            последнееСистемное = служебное
            последнееМоё = last.да("mine") && !служебное
            последнееКогда = last.строка("at") ?? ""
        } else {
            последнее = ""
            последнееСистемное = false
            последнееМоё = false
            последнееКогда = c.строка("updated") ?? ""
        }
    }
}

/// Одно сообщение переписки.
struct ЧатСообщение: Identifiable, Hashable, Decodable {
    let id: String
    let моё: Bool
    let тип: String
    let текст: String
    let когда: String
    /// Фото в сообщении, если сервер прислал адрес (meta.url).
    let фото: URL?
    /// Служебное уведомление («Продавец вышел из чата», «Покупатель отозвал своё предложение.») — у сайта это строка
    /// .kc-sys по центру, без автора и без облака.
    let системное: Bool
    /// Этап 45: уведомление о предложении, принятом или подкреплённом (kind offer_ok / offer_funded), — зелёное, как у
    /// mkChatBubble витрины.
    let хорошее: Bool
    /// Этап 45: служебное сообщение с meta.request — карточка заявки мастеру (_dmRender кабинета, карта §6.9.1).
    let заявка: ЗаявкаВЧате?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: ЧатКлюч.self)
        моё = c.да("mine")
        тип = c.строка("type") ?? "text"
        текст = c.строка("text") ?? ""
        когда = c.строка("at") ?? ""
        /* Владелец 25.09.2026, проверка на телефоне, сборка 33: «Продавец вышел из чата» пришло серым облаком
           собеседника. Сервер кладёт уведомления в переписку обычными сообщениями с автором (mine — кто вызвал
           событие), а приложение читало только mine/type/text и не могло их отличить. Все поля — терпимым разбором:
           нет поля — просто «нет». Этап 45 (владелец 26.09.2026): поля — только проверенные по коду кабинета (карта
           §6.4.10), догадки (sys, is_system, notice, event…) убраны. */
        let вид = c.строка("kind") ?? ""
        системное = Self.этоУведомление(роль: c.строка("role") ?? "", вид: вид, тип: тип, текст: текст)
        хорошее = вид == "offer_ok" || вид == "offer_funded"
        if let meta = try? c.nestedContainer(keyedBy: ЧатКлюч.self, forKey: ЧатКлюч("meta")) {
            /* У dm.php адрес медиа — в meta.url (карта §6.4.10); src — прежний запасной ключ этапа 3. */
            if let адрес = meta.строка("url") ?? meta.строка("src") {
                фото = тип == "image" ? Config.url(адрес) : nil
            } else {
                фото = nil
            }
            заявка = тип == "system" && meta.да("request") ? ЗаявкаВЧате(meta) : nil
        } else {
            фото = nil
            заявка = nil
        }
        /* У сообщения своего номера в июльском контракте не было. Берём его, если сервер начал присылать; иначе —
           отправитель, время и текст: двух одинаковых сообщений в одну секунду от одного человека не бывает. */
        id = c.строка("id") ?? [c.строка("from") ?? (моё ? "me" : "peer"), когда, тип, текст].joined(separator: "|")
    }

    /// Что показать в пузыре и в списке диалогов для не-текстовых сообщений.
    static func подпись(тип: String, текст: String) -> String {
        switch тип {
        case "image": return "📷 " + ChatText.т("photo")
        case "voice": return "🎤 " + ChatText.т("voice")
        /* Этап 45: запрос аренды и предложение обмена — подписи строки инбокса сайта (dm_rental_req, dm_exchange_offer);
           их карточки с кнопками пока на сайте. */
        case "rental" where Config.нативныеСообщенияКабинета: return ИнбоксText.т("rental_req")
        case "exchange" where Config.нативныеСообщенияКабинета: return ИнбоксText.т("exchange_offer")
        default:      return текст
        }
    }

    var подпись: String { Self.подпись(тип: тип, текст: текст) }

    /// Виды уведомлений о предложении цены — MK_CHAT_SYS_KINDS витрины (MK27 @568555): mkChatBubble рисует их строкой
    /// .kc-sys. Кабинет их не знает, но карта кабинета (§6.4.10) советует считать их служебными и в нём.
    static let видыУведомлений: Set<String> = ["offer_funded", "offer_unfunded", "offer_no", "offer_ok"]

    /**
     Служебное ли сообщение — ЭТАП 45 (владелец 26.09.2026), по проверенным полям карты кабинета (§6.4.10), а не догадкам:
       · type === "system" — так помечает служебное dm.php (_dmRender кабинета, CAB @1257484);
       · role === "system" — так помечает его chat.php (лид-чат, CAB @1193300; виджет витрины);
       · kind ∈ MK_CHAT_SYS_KINDS — уведомления о предложении цены (витрина рисует их пилюлей).
     Других признаков (kind "system", is_system, sys, notice, event) ни кабинет, ни витрина не читают — прежний список
     догадок этапа 3 убран. Предложение, встречное и обмен контактами (offer, counter, contact) — слова человека.
     Последняя страховка — точные фразы сервера, виденные на телефоне (сборка 33): как сервер помечает «Покупатель отозвал
     своё предложение» и «Продавец вышел из чата», из кода сайта не видно (карта §6.4.10: INFERRED), а на телефоне они
     пришли облаком с mine = true. Фраза проверяется целиком, от начала до конца строки.
     */
    static func этоУведомление(роль: String, вид: String, тип: String, текст: String) -> Bool {
        if роль.lowercased() == "system" { return true }
        if тип.lowercased() == "system" { return true }
        if видыУведомлений.contains(вид.lowercased()) { return true }
        return похожеНаСобытие(текст)
    }

    /// Текст — одна из фраз-уведомлений сервера целиком: «Продавец вышел из чата», «Покупатель вернулся в чат»,
    /// «Покупатель отозвал своё предложение.». Шаблон привязан к началу и концу строки: сообщение, где человек сам
    /// написал что-то похожее среди других слов, не попадёт. Буква «ё» — в составленном виде, как её пишет сервер.
    static func похожеНаСобытие(_ текст: String) -> Bool {
        let строка = текст.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !строка.isEmpty, строка.count <= 80 else { return false }
        return строка.range(of: шаблонСобытия, options: .regularExpression) != nil
    }

    private static let шаблонСобытия =
        "^(Покупатель|Продавец) (вышел из чата|вернулся в чат|отозвал сво[её] предложение)\\.?$"
}

/// Переписка: open / poll / send отдают её целиком.
struct ЧатПереписка: Decodable {
    let id: String
    let сообщения: [ЧатСообщение]
    /// Этап 45: thread.peer_read_at — когда собеседник прочитал переписку («✓✓ Прочитано» под последним моим, §6.4.8 i).
    let прочиталДо: String

    private struct Любое: Decodable {
        let значение: ЧатСообщение?
        init(from decoder: Decoder) throws { значение = try? ЧатСообщение(from: decoder) }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: ЧатКлюч.self)
        id = c.строка("id") ?? c.строка("tid") ?? ""
        сообщения = ((try? c.decode([Любое].self, forKey: ЧатКлюч("messages"))) ?? []).compactMap(\.значение)
        прочиталДо = c.строка("peer_read_at") ?? ""
    }
}

/// Ответ dm.php: ok, error, blocked и одно из — threads (list) или thread (open/poll/send).
struct ЧатОтвет: Decodable {
    let ok: Bool
    let ошибка: String?
    let заблокирован: Bool
    let диалоги: [ЧатДиалог]
    let переписка: ЧатПереписка?

    private struct ЛюбойДиалог: Decodable {
        let значение: ЧатДиалог?
        init(from decoder: Decoder) throws { значение = try? ЧатДиалог(from: decoder) }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: ЧатКлюч.self)
        ok = c.да("ok")
        ошибка = c.строка("error")
        заблокирован = c.да("blocked")
        диалоги = ((try? c.decode([ЛюбойДиалог].self, forKey: ЧатКлюч("threads"))) ?? []).compactMap(\.значение)
        переписка = try? c.decode(ЧатПереписка.self, forKey: ЧатКлюч("thread"))
    }
}

/**
 Заявка мастеру в личной переписке — ЭТАП 45 (владелец 26.09.2026). dm.php присылает её служебным сообщением
 type "system" с meta{request: true, rid, master_id, assigned, confirmed, litem_id, litem_title, mname, mrating, mrcnt,
 mdeals, mverified, msvcd, msvct} (карта §6.9.1), и кабинет рисует вместо пилюли карточку (_dmRender, CAB @1257484).
 */
struct ЗаявкаВЧате: Hashable {
    let номер: String
    let мастер: String
    let назначена: Bool
    let подтверждена: Bool
    let объявлениеID: String
    let объявление: String
    let имяМастера: String
    let рейтинг: Double
    let отзывов: Int
    let сделок: Int
    let проверен: Bool
    let услугВыполнено: Int
    let услугВсего: Int

    init(_ m: KeyedDecodingContainer<ЧатКлюч>) {
        номер = m.строка("rid") ?? ""
        мастер = m.строка("master_id") ?? ""
        назначена = m.да("assigned")
        подтверждена = m.да("confirmed")
        объявлениеID = m.строка("litem_id") ?? ""
        объявление = m.строка("litem_title") ?? ""
        имяМастера = m.строка("mname") ?? ""
        рейтинг = m.дробное("mrating")
        отзывов = m.целое("mrcnt")
        сделок = m.целое("mdeals")
        проверен = m.да("mverified")
        услугВыполнено = m.целое("msvcd")
        услугВсего = m.целое("msvct")
    }

    /// _reqMasterProfile: профиль мастера показывается, если есть хоть что-то из имени, рейтинга, сделок, отметки, услуг.
    var естьПрофиль: Bool {
        !имяМастера.isEmpty || рейтинг > 0 || сделок > 0 || проверен || услугВсего > 0
    }
}
