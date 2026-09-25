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
            последнее = ЧатСообщение.подпись(тип: last.строка("type") ?? "text", текст: last.строка("text") ?? "")
            последнееМоё = last.да("mine")
            последнееКогда = last.строка("at") ?? ""
        } else {
            последнее = ""
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

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: ЧатКлюч.self)
        моё = c.да("mine")
        тип = c.строка("type") ?? "text"
        текст = c.строка("text") ?? ""
        когда = c.строка("at") ?? ""
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
