import Foundation

/**
 ОФЛАЙН-КОПИИ НА ДИСКЕ (владелец 08.10.2026: «без сети человек должен видеть последнее, что видел»).

 Что уже было до этого и осталось как есть:
   · лента — ListingsCache (kliko-listings-first.json и полная выдача), главная — КэшГлавной, стартовые данные — Seed;
   · избранное — само живёт на телефоне (ИзбранноеФайл: карточки сетки, вне резервной копии);
   · «Мои объявления», «Мои сделки» и список «Чата» — КэшКабинета (Caches, kliko-cabinet-lists-v1, с номером вошедшего);
   · карточки объявлений из избранного и «Вы смотрели» — ListingDetailCache; виджет — снимок в App Group.

 Здесь — то, чего не было: последние открытые карточки сделок и переписки (личные dm.php, чат по объявлению и чат лида
 chat.php). Тело ответа сайта лежит как пришло, разбирает его тот же код, что живой ответ, — второго формата на диске
 нет. Пишет экран после каждой удачной загрузки (одинаковое второй раз не пишется — это решает сам экран), читает — когда
 сеть не ответила.

 Где: Caches/kliko-offline/<номер аккаунта>/<вид>/<ключ>.json. Запись атомарная, одной очередью, не на главной.
 Пределы: файл — не больше 1 МБ, переписка — последние 200 сообщений, на вид — 20 файлов (лишние — самые давние по
 времени записи, то есть по последнему открытию со связью).

 🔴 ТОЛЬКО СВОЁ. Папка — номера вошедшего (СессияПриложения.id). Пока страница не сказала номер (холодный запуск без
 сети), берётся номер последнего, кто входил на этом телефоне, — и только если подсказка сессии говорит «вошёл». Вошёл
 другой номер — папка прежнего уходит. Выход из аккаунта стирает всё (ВыходНачисто), а ответы, что ещё в пути, — мимо
 диска (поколение).
 */
enum КопииБезСети {
    /// Вид копии — своя папка и свой предел файлов.
    enum Вид: String {
        case сделка = "deals"
        case переписка = "chats"

        /// Сколько последних держать: 20 карточек сделок и 20 переписок.
        var предел: Int { 20 }
    }

    /// Копия с диска и когда она легла.
    struct Копия: Sendable {
        let данные: Data
        let когда: Date
    }

    /// Больше — уже не карточка и не переписка: не храним.
    static let размер = 1024 * 1024
    /// Сообщений в переписке на диске — последние.
    static let сообщений = 200

    /// Запись, подрезка, чтение и стирание — по порядку, одной очередью: стирание при выходе не обгонит запись.
    private static let очередь = DispatchQueue(label: "kz.kliko.offline-copies", qos: .utility)
    private static let замок = NSLock()
    /// Поколение копий: выход его меняет. Только под замком.
    private static var счётчик = 0
    /// Номер последнего вошедшего — для холодного запуска без сети.
    private static let ключВладельца = "kliko.offline.owner"
    /// Что можно в имени файла и папки: номер приходит от сайта, «../» не должен вывести запись наружу.
    private static let допустимые: Set<Character> =
        Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")

    private static var корень: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("kliko-offline", isDirectory: true)
    }

    static var поколение: Int {
        замок.lock()
        defer { замок.unlock() }
        return счётчик
    }

    // MARK: - Чьи копии

    /**
     Номер аккаунта для папки: вошедший сейчас; пока номер не известен, а подсказка сессии говорит «вошёл», — последний
     вошедший на этом телефоне. Гость или неизвестно — пусто: копий нет.
     */
    @MainActor
    static func владелец() -> String {
        let сессия = СессияПриложения.shared
        guard сессия.вошёл == true else { return "" }
        let хранилище = UserDefaults.standard
        let прежний = хранилище.string(forKey: ключВладельца) ?? ""
        let сейчас = годный(сессия.id) ? сессия.id : ""
        guard !сейчас.isEmpty else { return годный(прежний) ? прежний : "" }
        if прежний != сейчас {
            хранилище.set(сейчас, forKey: ключВладельца)
            /* Вошёл другой номер — копии прежнего на этом телефоне больше ничьи. */
            if годный(прежний), let папка = корень?.appendingPathComponent(прежний, isDirectory: true) {
                очередь.async { try? FileManager.default.removeItem(at: папка) }
            }
        }
        return сейчас
    }

    // MARK: - Запись

    /// Тело ответа как пришло (JSON). Переписка в нём обрезается до последних сообщений — уже на очереди.
    @MainActor
    static func сохранить(тело: Data, вид: Вид, ключ: String) {
        guard let папка = папка(вид), let имя = имяФайла(ключ) else { return }
        let взятое = поколение
        очередь.async {
            guard взятое == КопииБезСети.поколение,
                  var поля = (try? JSONSerialization.jsonObject(with: тело)) as? [String: Any] else { return }
            var данные = тело
            if КопииБезСети.обрезать(&поля), JSONSerialization.isValidJSONObject(поля),
               let короче = try? JSONSerialization.data(withJSONObject: поля) {
                данные = короче
            }
            КопииБезСети.записать(данные, в: папка, имя: имя, предел: вид.предел)
        }
    }

    /// Готовые байты (разобранный ответ, обрезанный данныеКопии) — только запись.
    @MainActor
    static func записатьГотовое(_ данные: Data, вид: Вид, ключ: String) {
        guard данные.count <= размер, let папка = папка(вид), let имя = имяФайла(ключ) else { return }
        let взятое = поколение
        очередь.async {
            guard взятое == КопииБезСети.поколение else { return }
            КопииБезСети.записать(данные, в: папка, имя: имя, предел: вид.предел)
        }
    }

    /// Байты копии из словаря: переписка обрезана, ключи по порядку (одинаковый ответ — одинаковые байты, и экран может
    /// не писать его второй раз). Не JSON или больше предела — nil.
    static func данныеКопии(_ поля: [String: Any]) -> Data? {
        var копия = поля
        _ = обрезать(&копия)
        guard JSONSerialization.isValidJSONObject(копия),
              let данные = try? JSONSerialization.data(withJSONObject: копия, options: [.sortedKeys]),
              данные.count <= размер else { return nil }
        return данные
    }

    // MARK: - Чтение

    /// Копия или nil. Читаем на той же очереди — после записей, поставленных раньше.
    @MainActor
    static func прочитать(вид: Вид, ключ: String) async -> Копия? {
        guard let папка = папка(вид), let имя = имяФайла(ключ) else { return nil }
        let файл = папка.appendingPathComponent(имя)
        return await withCheckedContinuation { (готово: CheckedContinuation<Копия?, Never>) in
            очередь.async {
                guard let данные = try? Data(contentsOf: файл), !данные.isEmpty else {
                    готово.resume(returning: nil)
                    return
                }
                let свойства = try? файл.resourceValues(forKeys: [.contentModificationDateKey])
                готово.resume(returning: Копия(данные: данные, когда: свойства?.contentModificationDate ?? Date()))
            }
        }
    }

    /// Копия разобранным словарём (сделка, чат лида) или nil.
    @MainActor
    static func прочитатьПоля(вид: Вид, ключ: String) async -> (поля: [String: Any], когда: Date)? {
        guard let копия = await прочитать(вид: вид, ключ: ключ),
              let поля = (try? JSONSerialization.jsonObject(with: копия.данные)) as? [String: Any] else { return nil }
        return (поля, копия.когда)
    }

    // MARK: - Стирание

    /// Выход из аккаунта: все копии долой, ответы в пути — мимо диска, номер последнего вошедшего забыт.
    static func стереть() {
        замок.lock()
        счётчик += 1
        замок.unlock()
        UserDefaults.standard.removeObject(forKey: ключВладельца)
        guard let все = корень else { return }
        очередь.async { try? FileManager.default.removeItem(at: все) }
    }

    // MARK: - Внутреннее

    @MainActor
    private static func папка(_ вид: Вид) -> URL? {
        let чей = владелец()
        guard !чей.isEmpty else { return nil }
        return корень?.appendingPathComponent(чей, isDirectory: true)
            .appendingPathComponent(вид.rawValue, isDirectory: true)
    }

    private static func годный(_ номер: String) -> Bool {
        !номер.isEmpty && номер.count <= 64 && номер.allSatisfy { допустимые.contains($0) }
    }

    /// Ключ → имя файла: чужие знаки — «_», не длиннее 96.
    private static func имяФайла(_ ключ: String) -> String? {
        let чистый = String(ключ.prefix(96).map { допустимые.contains($0) ? $0 : "_" })
        guard !чистый.isEmpty, чистый.contains(where: { $0 != "_" && $0 != "-" }) else { return nil }
        return чистый + ".json"
    }

    /// Последние сообщения переписки: messages сверху (widget_data), в chat (poll, seller_chat) и в thread (dm.php).
    /// Вернёт true, если что-то обрезано.
    private static func обрезать(_ поля: inout [String: Any]) -> Bool {
        var обрезано = false
        if let лента = поля["messages"] as? [Any], лента.count > сообщений {
            поля["messages"] = Array(лента.suffix(сообщений))
            обрезано = true
        }
        for ключ in ["chat", "thread"] {
            guard var вложенный = поля[ключ] as? [String: Any],
                  let лента = вложенный["messages"] as? [Any], лента.count > сообщений else { continue }
            вложенный["messages"] = Array(лента.suffix(сообщений))
            поля[ключ] = вложенный
            обрезано = true
        }
        return обрезано
    }

    /// Только на очереди: файл атомарно, папка — вне резервной копии, лишние файлы вида — прочь.
    private static func записать(_ данные: Data, в папка: URL, имя: String, предел: Int) {
        guard данные.count <= размер else { return }
        let диск = FileManager.default
        do {
            try диск.createDirectory(at: папка, withIntermediateDirectories: true)
            if var общая = корень {
                var значения = URLResourceValues()
                значения.isExcludedFromBackup = true
                try? общая.setResourceValues(значения)
            }
            try данные.write(to: папка.appendingPathComponent(имя), options: .atomic)
        } catch {
            return      // диск полон — копия удобство, а не обязанность
        }
        guard let файлы = try? диск.contentsOfDirectory(at: папка, includingPropertiesForKeys: [.contentModificationDateKey],
                                                       options: [.skipsHiddenFiles]),
              файлы.count > предел else { return }
        let поВремени = файлы.map { файл -> (URL, Date) in
            let когда = (try? файл.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return (файл, когда ?? .distantPast)
        }.sorted { $0.1 > $1.1 }
        for (файл, _) in поВремени.dropFirst(предел) { try? диск.removeItem(at: файл) }
    }
}
