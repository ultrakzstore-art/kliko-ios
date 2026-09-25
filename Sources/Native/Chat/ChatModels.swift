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
            let служебное = ЧатСообщение.этоУведомление(
                роль: last.строка("role") ?? c.строка("last_role") ?? "",
                вид: last.строка("kind") ?? c.строка("last_kind") ?? "",
                тип: типПоследнего,
                флаг: last.да("sys") || last.да("system") || last.да("is_system"),
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

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: ЧатКлюч.self)
        моё = c.да("mine")
        тип = c.строка("type") ?? "text"
        текст = c.строка("text") ?? ""
        когда = c.строка("at") ?? ""
        /* Владелец 25.09.2026, проверка на телефоне, сборка 33: «Продавец вышел из чата» пришло серым облаком
           собеседника. Сервер кладёт уведомления в переписку обычными сообщениями с автором (mine — кто вызвал
           событие), а приложение читало только mine/type/text и не могло их отличить. Все поля — терпимым разбором:
           нет поля — просто «нет». */
        системное = Self.этоУведомление(роль: c.строка("role") ?? "", вид: c.строка("kind") ?? "", тип: тип,
                                        флаг: c.да("sys") || c.да("system") || c.да("is_system"), текст: текст)
        if let meta = try? c.nestedContainer(keyedBy: ЧатКлюч.self, forKey: ЧатКлюч("meta")),
           let адрес = meta.строка("url") ?? meta.строка("src") {
            фото = тип == "image" ? Config.url(адрес) : nil
        } else {
            фото = nil
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
        default:      return текст
        }
    }

    var подпись: String { Self.подпись(тип: тип, текст: текст) }

    /// Виды уведомлений о предложении цены — как MK_CHAT_SYS_KINDS сайта (mkChatBubble рисует их строкой .kc-sys).
    private static let видыСайта: Set<String> = ["offer_funded", "offer_unfunded", "offer_no", "offer_ok"]
    /// Виды событий переписки — отзыв предложения и присутствие (chat.php offer_withdraw, presence_event left/back).
    /// Как их помечает dm.php, не видели — берём и эти названия, и общие.
    private static let видыСобытий: Set<String> = ["offer_withdrawn", "offer_withdraw", "withdraw", "withdrawn",
                                                     "presence", "left", "back", "system", "sys", "event", "notice",
                                                     "service"]
    /// Тип сообщения, который означает уведомление, а не текст человека.
    private static let типыУведомлений: Set<String> = ["system", "sys", "event", "notice", "service", "info"]

    /// Служебное ли сообщение. role == "system" и виды сайта — как в mkChatBubble; остальное — на случай, если dm.php
    /// помечает иначе. Предложение, встречное и обмен контактами (offer, counter, contact) — слова человека, не
    /// уведомления. Последняя страховка — точные фразы сервера, виденные на телефоне.
    static func этоУведомление(роль: String, вид: String, тип: String, флаг: Bool, текст: String) -> Bool {
        let р = роль.lowercased()
        let в = вид.lowercased()
        let т = тип.lowercased()
        if р == "system" { return true }
        if видыСайта.contains(в) || видыСобытий.contains(в) { return true }
        if типыУведомлений.contains(т) { return true }
        if флаг { return true }
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

    private struct Любое: Decodable {
        let значение: ЧатСообщение?
        init(from decoder: Decoder) throws { значение = try? ЧатСообщение(from: decoder) }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: ЧатКлюч.self)
        id = c.строка("id") ?? c.строка("tid") ?? ""
        сообщения = ((try? c.decode([Любое].self, forKey: ЧатКлюч("messages"))) ?? []).compactMap(\.значение)
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
