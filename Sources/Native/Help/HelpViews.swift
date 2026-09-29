import SwiftUI
import UIKit

/**
 СПРАВОЧНЫЙ ЦЕНТР И СТАТИЧЕСКИЕ СТРАНИЦЫ САЙТА — СВОИМ ЭКРАНОМ (этап 50).

 Было: «Справочный центр» во вкладке «Кабинет», ссылки подвала (помощь, как работает гарант, PRO, правила, тарифы,
 соглашение, оферта, политика, оплата) открывали страницу сайта — всё приложение уходило на WKWebView под слоем.
 Стало: та же страница сайта качается (URLSession, без куки — страницы публичные), из неё вынимается статья
 (РазборСтатьи) и показывается своими блоками в оформлении приложения, светлом и тёмном: заголовки, абзацы, списки,
 вопросы-ответы раскрывашками, ссылки. Ссылка на другую такую страницу открывается здесь же, следующим экраном; якорь
 (#safe) — прокруткой; почта и телефон — системой; прочие адреса сайта — как обычно (окно закрывается, адрес идёт
 своим путём: нативный экран или сайт).

 Последняя удачная страница лежит в Caches по адресу с языком и открывается сразу, а свежая качается следом
 (ЗагрузкаСтатьи); без сети — копия с пометкой. Страница, из которой статью вынуть не удалось (собрана скриптом), —
 честно «открывается только на сайте» и кнопка сайта. Своих текстов справки у приложения нет: «Частые вопросы» и «Как
 работает Гарант» окна «Категории» — это help#faq и help#safe этой же страницы.

 Экран: первый h1 — заголовком над статьёй (если не повторяет шапку), разделы h2 — отдельными карточками (HelpBlocks),
 оглавление чипами, у справки — поиск по вопросам и тексту (ответ найденного вопроса раскрыт) и строка поддержки.
 Статьи справки (/help/<раздел>, help?topic=…) — тем же экраном. «Тарифы» — без цен, кнопок и ссылок покупки и без
 «Открыть на сайте» (правило App Store 3.1.1): только описание и «Эта возможность недоступна в приложении.».
 */

/// Статическая страница сайта: слаг, запрос (только у справки) и якорь.
struct СтраницаСайта: Hashable, Identifiable {
    /// help, soglashenie, … или статья справки «help/<раздел>».
    let слаг: String
    var якорь: String?
    /// Параметры адреса статьи справки (help?topic=…) без меток utm_; у прочих страниц — nil.
    var запрос: String? = nil

    var id: String { слаг + "?" + (запрос ?? "") + "#" + (якорь ?? "") }

    /// Страницы подвала сайта (home.html: /kz/ru/help, oplata, tarify, soglashenie, oferta, privacy).
    static let известные: Set<String> = ["help", "soglashenie", "oferta", "privacy", "oplata", "tarify"]

    /// Корень страницы: у статьи справки «help/<раздел>» — help.
    var корень: String { слаг.split(separator: "/").first.map(String.init) ?? слаг }

    /// Справка и её статьи — с поиском и строкой поддержки.
    var справка: Bool { корень == "help" }

    /// «Тарифы» — только описание, без цен и покупок (правило App Store 3.1.1).
    var тарифы: Bool { корень == "tarify" }

    /// Название, как в подвале сайта. У статьи справки своего нет — «Справочный центр» до загрузки.
    var заголовок: String { СправкаText.т("p_" + корень) }

    /// Своё ли это название (страница подвала) или у статьи лучше взять её h1.
    var названаПодвалом: Bool { слаг == корень && запрос == nil }

    private var хвост: String {
        guard let запрос, !запрос.isEmpty else { return слаг }
        return слаг + "?" + запрос
    }

    /// /kz/<язык телефона>/<слаг> — страница на языке приложения, даже если ссылка была на /kz/ru/.
    var адрес: URL? { Config.страницаСайта(хвост) }

    var адресСЯкорем: URL? {
        guard let якорь, !якорь.isEmpty else { return адрес }
        return Config.страницаСайта(хвост + "#" + якорь)
    }

    /**
     https://kliko.kz/kz/ru/help#safe, /soglashenie.php, /kz/kz/privacy, /kz/ru/help/safe, /help.php?topic=pay →
     страница; прочее — nil. Лишние параметры у страниц подвала (?print=1, ?utm_…) не мешают — страница та же; у
     справки они — выбор статьи и идут с адресом.
     */
    static func из(_ адрес: URL) -> СтраницаСайта? {
        let полный = адрес.absoluteURL
        guard let схема = полный.scheme?.lowercased(), схема == "https" || схема == "http",
              Config.deepLink(полный) != nil,
              let части = URLComponents(url: полный, resolvingAgainstBaseURL: false) else { return nil }
        var сегменты = части.path.lowercased().split(separator: "/").map(String.init)
        /* /kz/ru/… — регион и язык впереди. */
        if сегменты.count >= 2, сегменты[0].count == 2, сегменты[1].count == 2,
           сегменты[0].allSatisfy({ $0.isASCII && $0.isLetter }), сегменты[1].allSatisfy({ $0.isASCII && $0.isLetter }) {
            сегменты.removeFirst(2)
        }
        guard var первый = сегменты.first else { return nil }
        if первый.hasSuffix(".php") { первый = String(первый.dropLast(4)) }
        guard известные.contains(первый) else { return nil }
        var слаг = первый
        if сегменты.count > 1 {
            /* Вложенные адреса — только статьи справки: /help/<раздел>[/<статья>]. */
            let вложенные = Array(сегменты.dropFirst())
            let годные = вложенные.allSatisfy { часть in
                !часть.isEmpty && часть.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
            }
            guard первый == "help", вложенные.count <= 2, годные else { return nil }
            слаг = первый + "/" + вложенные.joined(separator: "/")
        }
        var запрос: String? = nil
        if первый == "help" {
            let параметры = (части.queryItems ?? []).filter { !$0.name.lowercased().hasPrefix("utm_") }
            if !параметры.isEmpty {
                var чистые = URLComponents()
                чистые.queryItems = параметры
                запрос = чистые.percentEncodedQuery
            }
        }
        let якорь = (части.fragment ?? "").trimmingCharacters(in: .whitespaces)
        return СтраницаСайта(слаг: слаг, якорь: якорь.isEmpty ? nil : якорь, запрос: запрос)
    }

    /// Та же страница (без учёта якоря).
    func таЖе(_ другая: СтраницаСайта) -> Bool {
        слаг == другая.слаг && (запрос ?? "") == (другая.запрос ?? "")
    }
}

extension СтатьяСайта {
    /**
     Куда прокрутить по якорю адреса. Сначала — элемент с таким id/name. Якорь «частых вопросов» (faq), которого на
     странице нет, — к первому вопросу-ответу (<details>) страницы, а если над ним заголовок — к заголовку: у сайта
     раздел вопросов может называться как угодно, а ссылка приложения остаётся одной.
     */
    func цель(якоря якорь: String) -> Int? {
        if let точная = блок(якоря: якорь) { return точная }
        let вопросы: Set<String> = ["faq", "faqs", "voprosy", "questions"]
        guard вопросы.contains(якорь.lowercased()) else { return nil }
        guard let номер = блоки.firstIndex(where: { блок in
            if case .вопрос = блок.вид { return true }
            return false
        }) else { return nil }
        if номер > 0, case .заголовок = блоки[номер - 1].вид {
            return блоки[номер - 1].id
        }
        return блоки[номер].id
    }

    /// Раздел этой страницы по названию (без регистра, эмодзи и знаков, «ё» = «е»): заголовок h1–h4.
    func раздел(названный название: String) -> Int? {
        let искомый = РазборСтатьи.ключРаздела(название)
        guard !искомый.isEmpty else { return nil }
        let первый = первыйЗаголовок?.id
        for блок in блоки where блок.id != первый {
            guard case .заголовок(let уровень) = блок.вид, уровень <= 4 else { continue }
            if РазборСтатьи.ключРаздела(блок.простой) == искомый { return блок.id }
        }
        return nil
    }

    /// Слова адреса, что называют раздел: якорь (#start), слово пути (help/start), значения параметров (help?sec=start).
    static func слова(_ другая: СтраницаСайта) -> [String] {
        var слова: [String] = []
        if let якорь = другая.якорь, !якорь.isEmpty { слова.append(якорь) }
        let части = другая.слаг.split(separator: "/")
        if части.count > 1, let последняя = части.last { слова.append(String(последняя)) }
        if let запрос = другая.запрос, let параметры = URLComponents(string: "?" + запрос)?.queryItems {
            for параметр in параметры {
                if let значение = параметр.value, !значение.isEmpty { слова.append(значение) }
            }
        }
        return слова
    }

    /**
     Куда на этой странице ведёт раздел — по порядку:
       (а) как у сайта: якорь (id/name, «faq» — к вопросам), метка панели (id, data-sec, data-cat, … — сравнение без
           приставок sec-, hc-, help-), якорь без приставок;
       (б) заголовок с тем же названием (без регистра, эмодзи и номера), потом — начинающийся с названия.
     Видимый заголовок — прокрутка к нему; скрытая панель или раздел без заголовка — раздел своим видом.
     Вторая часть итога — путь поиска (для журнала отладки).
     */
    func переход(слова: [String], название: String, подпись: String, плитка: Int?) -> (ПереходПлитки, String)? {
        for слово in слова where !слово.isEmpty {
            let ключ = РазборСтатьи.ключЯкоря(слово)
            let группа: [БлокСтатьи] = ключ.isEmpty ? [] : блоки.filter { !Self.этоПлитка($0) && $0.группы.contains(ключ) }
            if let найден = цель(якоря: слово), let блок = блоки.first(where: { $0.id == найден }), !Self.этоПлитка(блок) {
                /* Якорь в скрытой панели — вся панель (её метка), а не один блок. */
                if блок.скрыт, !группа.isEmpty {
                    return (вид(группы: группа, название: название, подпись: подпись, плитка: плитка),
                            "якорь «\(слово)» в скрытой панели (\(группа.count))")
                }
                return (вид(для: блок, название: название, подпись: подпись, плитка: плитка), "якорь «\(слово)»")
            }
            guard !ключ.isEmpty else { continue }
            if !группа.isEmpty {
                return (вид(группы: группа, название: название, подпись: подпись, плитка: плитка),
                        "метка панели «\(ключ)» (\(группа.count))")
            }
            if let блок = блоки.first(where: { блок in
                !Self.этоПлитка(блок) && блок.якоря.contains(where: { РазборСтатьи.ключЯкоря($0) == ключ })
            }) {
                return (вид(для: блок, название: название, подпись: подпись, плитка: плитка), "якорь без приставки «\(ключ)»")
            }
        }
        /* Документ (соглашение, оферта, политика): «soglashenie#s6», «#punkt-4-2» без такого id — раздел или пункт с этим
           номером («6 Ответственность», «4.2.»). */
        for слово in слова where !слово.isEmpty {
            guard let номер = РазборСтатьи.номерИзЯкоря(слово), let найден = self.блок(номера: номер) else { continue }
            return (вид(для: найден, название: название, подпись: подпись, плитка: плитка), "номер «\(номер)»")
        }
        let искомый = РазборСтатьи.ключРаздела(Self.безНомера(название))
        guard !искомый.isEmpty else { return nil }
        let первый = первыйЗаголовок?.id
        var похожий: БлокСтатьи? = nil
        for блок in блоки where блок.id != первый {
            guard case .заголовок(let уровень) = блок.вид, уровень <= 4 else { continue }
            let свой = РазборСтатьи.ключРаздела(Self.безНомера(блок.простой))
            if свой == искомый {
                return (вид(для: блок, название: название, подпись: подпись, плитка: плитка), "заголовок «\(блок.простой)»")
            }
            if похожий == nil, искомый.count >= 4, свой.count >= 4, свой.hasPrefix(искомый) || искомый.hasPrefix(свой) {
                похожий = блок
            }
        }
        if let похожий {
            return (вид(для: похожий, название: название, подпись: подпись, плитка: плитка),
                    "похожий заголовок «\(похожий.простой)»")
        }
        return nil
    }

    /**
     (г) Последнее средство: вопросы страницы (и скрытых панелей), где есть слова названия или подписи плитки
     (по началу слова: «регистрация» — «регистрации»). Пусто — раздел покажет «пока нет ответов».
     */
    func вопросы(оТеме название: String, подпись: String) -> [БлокСтатьи] {
        func основы(_ текст: String) -> [String] {
            текст.lowercased().split(whereSeparator: { !$0.isLetter }).compactMap { (слово: Substring) -> String? in
                guard слово.count >= 4 else { return nil }
                return String(слово.prefix(5)).replacingOccurrences(of: "ё", with: "е")
            }
        }
        for основа in [основы(название), основы(подпись)] where !основа.isEmpty {
            let найдено = блоки.filter { блок in
                guard case .вопрос = блок.вид else { return false }
                let текст = блок.простой.lowercased().replacingOccurrences(of: "ё", with: "е")
                return основа.contains(where: { текст.contains($0) })
            }
            if !найдено.isEmpty { return найдено }
        }
        return []
    }

    /// Заголовок с этим номером («6» — «6 Ответственность»), иначе пункт с таким маркером («4.2» — «4.2.»).
    func блок(номера номер: String) -> БлокСтатьи? {
        let первый = первыйЗаголовок?.id
        let заголовок = блоки.first(where: { блок in
            guard блок.id != первый, case .заголовок(let уровень) = блок.вид, уровень <= 4,
                  let свой = РазборСтатьи.номерЗаголовка(блок.простой) else { return false }
            return РазборСтатьи.чистыйНомер(свой.номер) == номер
        })
        if let заголовок { return заголовок }
        return блоки.first(where: { блок in
            guard case .пункт(let маркер, _) = блок.вид else { return false }
            return РазборСтатьи.чистыйНомер(маркер) == номер
        })
    }

    private static func этоПлитка(_ блок: БлокСтатьи) -> Bool {
        if case .карточка = блок.вид { return true }
        return false
    }

    /// «1 Оператор данных» → «Оператор данных»: номер сайта названию не мешает.
    private static func безНомера(_ текст: String) -> String {
        РазборСтатьи.номерЗаголовка(текст)?.название ?? текст
    }

    /// Блок нашёлся: виден — прокрутка; в скрытой панели — его раздел своим видом.
    private func вид(для блок: БлокСтатьи, название: String, подпись: String, плитка: Int?) -> ПереходПлитки {
        guard блок.скрыт else { return .прокрутка(блок.id) }
        let свои = блоки.filter { !Self.этоПлитка($0) && !$0.группы.isEmpty && $0.группы == блок.группы }
        let раздел = свои.count >= 2 ? свои : блокиРаздела(от: блок.id)
        return .раздел(ОтборРаздела(название: название.isEmpty ? блок.простой : название, подпись: подпись,
                                    блоки: раздел, откуда: плитка))
    }

    /// Панель нашлась: видимый заголовок в ней (или один видимый блок) — прокрутка; иначе — её блоки своим видом.
    private func вид(группы: [БлокСтатьи], название: String, подпись: String, плитка: Int?) -> ПереходПлитки {
        let видимые = группы.filter { !$0.скрыт }
        if let первый = видимые.first {
            if case .заголовок = первый.вид { return .прокрутка(первый.id) }
            /* Панель вся на странице (не скрыта) — к её началу, а не копией своим видом. */
            if группы.count == 1 || видимые.count == группы.count { return .прокрутка(первый.id) }
        }
        return .раздел(ОтборРаздела(название: название.isEmpty ? (группы.first?.простой ?? "") : название,
                                    подпись: подпись, блоки: группы, откуда: плитка))
    }

    /// Раздел от блока: до следующего заголовка того же уровня или выше, в той же видимости (без плиток).
    private func блокиРаздела(от id: Int) -> [БлокСтатьи] {
        guard let начало = блоки.firstIndex(where: { $0.id == id }) else { return [] }
        let первый = блоки[начало]
        var уровень = 7
        if case .заголовок(let свой) = первый.вид { уровень = свой }
        var итог = [первый]
        var номер = начало + 1
        while номер < блоки.count {
            let блок = блоки[номер]
            if блок.скрыт != первый.скрыт { break }
            if case .заголовок(let свой) = блок.вид, свой <= уровень { break }
            if !Self.этоПлитка(блок) { итог.append(блок) }
            номер += 1
        }
        return итог
    }
}

/// Куда ведёт плитка раздела: прокрутка к блоку страницы или раздел своим видом.
enum ПереходПлитки {
    case прокрутка(Int)
    case раздел(ОтборРаздела)
}

/// Раздел справки своим видом (панель сайта, что открывается по плитке, или вопросы по теме): название, подпись,
/// блоки; «Все разделы» возвращает к плитке, откуда пришли.
struct ОтборРаздела {
    let название: String
    let подпись: String
    let блоки: [БлокСтатьи]
    let откуда: Int?
}

// MARK: - Загрузка

/**
 Загрузка статьи: «сначала своё, потом свежее» (stale-while-revalidate), отдельно для каждого языка — ключ копии и
 памяти — полный адрес /kz/<язык>/<слаг>.
   · Есть разобранная за этот запуск или копия на диске — показывается сразу, без крутилки.
   · Следом, в фоне, страница качается заново; изменилась — статья на экране тихо заменяется, копия на диске
     обновляется. Не чаще раза в «свежести» за запуск (потянуть вниз — всегда заново).
   · Сети нет: показана копия — пометка «сохранённая копия»; копии нет — встроенная заглушка с «Повторить»
     (текстов справки в приложении нет — их правит команда сайта).
 */
@MainActor
final class ЗагрузкаСтатьи: ObservableObject {
    enum Состояние {
        case идёт
        case готово(СтатьяСайта, изКопии: Bool)
        case пусто
        case ошибка
    }

    @Published private(set) var состояние: Состояние = .идёт

    let страница: СтраницаСайта

    /// Разобранная статья и сырая страница, из которой она вышла.
    private struct Запомненная {
        let статья: СтатьяСайта
        let данные: Data
    }

    /// Разобранные за этот запуск (по адресу с языком).
    private static var память: [String: Запомненная] = [:]
    /// Когда адрес последний раз удачно сверен с сайтом за этот запуск.
    private static var сверено: [String: Date] = [:]
    /// Сколько секунд страница считается свежей и не качается заново (кроме «потянуть вниз»).
    private static let свежесть: TimeInterval = 300

    init(страница: СтраницаСайта) {
        self.страница = страница
    }

    /// Заранее положить страницу в память и на диск (окно «Категории», кабинет): открытие справки — мгновенное.
    static func прогреть(_ страница: СтраницаСайта) async {
        let загрузка = ЗагрузкаСтатьи(страница: страница)
        await загрузка.загрузить()
    }

    func загрузить(заново: Bool = false) async {
        guard let адрес = страница.адрес else {
            состояние = .ошибка
            return
        }
        let ключ = адрес.absoluteString

        /* 1. Сразу — своё: память этого запуска или копия на диске. */
        var показана: Data? = nil
        if case .готово = состояние {
            показана = Self.память[ключ]?.данные
        }
        if показана == nil, let запомненная = Self.память[ключ] {
            состояние = .готово(запомненная.статья, изКопии: false)
            показана = запомненная.данные
        }
        if показана == nil, let копия = Self.копия(ключ: ключ) {
            let статья = await Self.разобрать(String(decoding: копия, as: UTF8.self), адрес: адрес, тарифы: страница.тарифы)
            if статья.годится {
                Self.память[ключ] = Запомненная(статья: статья, данные: копия)
                состояние = .готово(статья, изКопии: false)
                показана = копия
            }
        }

        /* 2. Свежее с сайта — если давно не сверяли или просят заново. */
        if !заново, показана != nil, let когда = Self.сверено[ключ], Date().timeIntervalSince(когда) < Self.свежесть {
            return
        }
        if показана == nil { состояние = .идёт }
        var запрос = URLRequest(url: адрес, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        запрос.setValue("text/html", forHTTPHeaderField: "Accept")
        do {
            let (данные, ответ) = try await URLSession.shared.data(for: запрос)
            let код = (ответ as? HTTPURLResponse)?.statusCode ?? 0
            guard код == 200, !данные.isEmpty else { throw URLError(.badServerResponse) }
            Self.сверено[ключ] = Date()
            if let показана, показана == данные {
                /* Не изменилась — статья на экране та же; снять пометку «копия», если была. */
                if case .готово(let статья, let изКопии) = состояние, изКопии {
                    состояние = .готово(статья, изКопии: false)
                }
                return
            }
            let статья = await Self.разобрать(String(decoding: данные, as: UTF8.self), адрес: адрес, тарифы: страница.тарифы)
            guard статья.годится else {
                /* Страница собрана скриптом: без копии — «только на сайте»; с копией — оставить копию. */
                if показана == nil { состояние = .пусто }
                return
            }
            Self.память[ключ] = Запомненная(статья: статья, данные: данные)
            Self.сохранить(данные, ключ: ключ)
            состояние = .готово(статья, изКопии: false)
        } catch {
            if case .готово(let статья, _) = состояние {
                состояние = .готово(статья, изКопии: true)
            } else {
                состояние = .ошибка
            }
        }
    }

    /// Разбор — не на главном потоке. «Тарифы» — сразу без цен и покупок: ни в памяти, ни на экране их нет.
    private static func разобрать(_ html: String, адрес: URL, тарифы: Bool) async -> СтатьяСайта {
        await Task.detached(priority: .userInitiated) { () -> СтатьяСайта in
            let статья = РазборСтатьи.разобрать(html, адрес: адрес)
            return тарифы ? РазборСтатьи.безПокупок(статья) : статья
        }.value
    }

    // MARK: Копия на диске

    private static func файл(_ ключ: String) -> URL? {
        guard let папка = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        var имя = ""
        for знак in ключ.unicodeScalars {
            let годен = знак.isASCII && (знак.properties.isAlphabetic || знак.properties.numericType != nil)
            имя.unicodeScalars.append(годен ? знак : "_")
        }
        return папка.appendingPathComponent("kliko-pages", isDirectory: true).appendingPathComponent(имя + ".html")
    }

    private static func сохранить(_ данные: Data, ключ: String) {
        guard let файл = файл(ключ) else { return }
        try? FileManager.default.createDirectory(at: файл.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? данные.write(to: файл, options: .atomic)
    }

    private static func копия(ключ: String) -> Data? {
        guard let файл = файл(ключ) else { return nil }
        return try? Data(contentsOf: файл)
    }
}

// MARK: - Окно со стопкой страниц

/// Корень окна: первая страница и следующие по ссылкам — своим стеком.
struct ОкноСтраницСайта: View {
    let первая: СтраницаСайта
    /// Адрес не из этих страниц — окно закрывается, адрес идёт своим путём.
    let открыть: (URL) -> Void
    /// «Написать в поддержку» — своя форма обращения (ЛистОбращения) после закрытия окна.
    let написать: () -> Void
    let закрыть: () -> Void

    @State private var путь: [СтраницаСайта] = []

    init(первая: СтраницаСайта, открыть: @escaping (URL) -> Void, написать: @escaping () -> Void,
         закрыть: @escaping () -> Void) {
        self.первая = первая
        self.открыть = открыть
        self.написать = написать
        self.закрыть = закрыть
    }

    var body: some View {
        NavigationStack(path: $путь) {
            экран(первая)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(СправкаText.т("close")) { закрыть() }
                    }
                }
                .navigationDestination(for: СтраницаСайта.self) { страница in
                    экран(страница)
                }
        }
        .tint(Theme.акцент)
        /* Окно поднимает UIKit: направление письма (арабский — справа налево) ставим сами, как корень слоя. */
        .оформлениеСайта(языка: ЯзыкПриложения.shared.код)
    }

    private func экран(_ страница: СтраницаСайта) -> some View {
        ЭкранСтраницыСайта(страница: страница, перейти: { следующая in путь.append(следующая) },
                           открыть: открыть, написать: написать)
    }
}

// MARK: - Экран статьи

struct ЭкранСтраницыСайта: View {
    let страница: СтраницаСайта
    let перейти: (СтраницаСайта) -> Void
    let открыть: (URL) -> Void
    let написать: () -> Void

    @StateObject private var загрузка: ЗагрузкаСтатьи
    /// Куда прокрутить (якорь из адреса, оглавление или ссылка на этой же странице).
    @State private var прокрутить: Int? = nil
    @State private var раскрытые: Set<Int> = []
    /// Якорь адреса и <details open> уже учтены (при обновлении статьи не прыгаем заново).
    @State private var начатоС: Bool = false
    @State private var поиск = ""
    /// Вопросы, раскрытые поиском: пустой запрос их снова сворачивает.
    @State private var раскрытоПоиском: Set<Int> = []
    /// Раздел, открытый плиткой своим видом (скрытая панель сайта, раздел без заголовка, вопросы по теме).
    @State private var отбор: ОтборРаздела? = nil
    /// Размеры, растущие с Dynamic Type вместе с текстом статьи (HelpBlocks): h1 не мельче абзацев.
    @ScaledMetric(relativeTo: .title) private var размерH1: CGFloat = 24
    @ScaledMetric(relativeTo: .footnote) private var размерЧипа: CGFloat = 13
    @ScaledMetric(relativeTo: .body) private var размерТекста: CGFloat = 15

    init(страница: СтраницаСайта, перейти: @escaping (СтраницаСайта) -> Void, открыть: @escaping (URL) -> Void,
         написать: @escaping () -> Void) {
        self.страница = страница
        self.перейти = перейти
        self.открыть = открыть
        self.написать = написать
        _загрузка = StateObject(wrappedValue: ЗагрузкаСтатьи(страница: страница))
    }

    private func т(_ ключ: String) -> String { СправкаText.т(ключ) }

    private var запросПоиска: String { поиск.trimmingCharacters(in: .whitespacesAndNewlines) }

    /*
     Шапка непрозрачная, краской страницы: системный поиск в панели (.searchable) на iOS 26 — стекло, и карточки,
     уехавшие вверх, просвечивали под «Закрыть» и полем поиска. Теперь поле поиска — своё, над прокруткой
     (шапкаПоиска), а прокрутка начинается под ним и под ним не проходит.
     */
    var body: some View {
        содержимое
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .navigationTitle(заголовокЭкрана)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.фонСтраницы, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .task { await загрузка.загрузить() }
    }

    /// Поле поиска справки над прокруткой: фон страницы и черта снизу, прокрутка — под ней.
    private var шапкаПоиска: some View {
        VStack(spacing: 0) {
            ПолеПоискаСправки(текст: $поиск)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 10)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            Rectangle()
                .fill(Theme.линия)
                .frame(height: 1)
                .accessibilityHidden(true)
        }
        .background(Theme.фонСтраницы)
    }

    /// Название в шапке: страница подвала — как в подвале; статья справки — её h1, когда загрузилась.
    private var заголовокЭкрана: String {
        guard !страница.названаПодвалом, case .готово(let статья, _) = загрузка.состояние else {
            return страница.заголовок
        }
        let своё = статья.заголовок.trimmingCharacters(in: .whitespacesAndNewlines)
        return своё.isEmpty || своё.count > 60 ? страница.заголовок : своё
    }

    @ViewBuilder
    private var содержимое: some View {
        switch загрузка.состояние {
        case .идёт:
            VStack(spacing: 12) {
                SiteSpinner()
                Text(т("loading"))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.текстВторой)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ошибка:
            /* Кнопки «на сайт» нет: адрес этой страницы снова открыл бы это же окно. */
            ПустоСайта(значок: "wifi.exclamationmark", заголовок: т("fail_t"), подпись: т("fail_s"),
                       кнопка: т("retry"), действие: { Task { await загрузка.загрузить(заново: true) } })
        case .пусто:
            if страница.тарифы {
                ПустоСайта(значок: "lock", заголовок: страница.заголовок, подпись: т("no_digital"))
            } else {
                ПустоСайта(значок: "doc.text", заголовок: т("empty_t"), кнопка: т("retry"),
                           действие: { Task { await загрузка.загрузить(заново: true) } })
            }
        case .готово(let статья, let изКопии):
            статьяВид(статья, изКопии: изКопии)
        }
    }

    private func статьяВид(_ статья: СтатьяСайта, изКопии: Bool) -> some View {
        ScrollViewReader { прокрутка in
            VStack(spacing: 0) {
                if страница.справка {
                    шапкаПоиска
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if изКопии {
                            ЗаметкаБизнеса(т("cached"), тон: .предупреждение, значок: "wifi.slash")
                        }
                        if страница.тарифы {
                            ЗаметкаБизнеса(т("no_digital"), тон: .серый, значок: "lock")
                        }
                        if !запросПоиска.isEmpty {
                            найденноеВид(статья)
                                .id(Self.верхПоиска)
                        } else if let отбор {
                            отборВид(отбор)
                        } else {
                            статьяЦеликом(статья)
                        }
                        if страница.справка {
                            поддержка
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                    /* На iPad строка не тянется во всю ширину — читать как на сайте. */
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .refreshable { await загрузка.загрузить(заново: true) }
                .environment(\.openURL, OpenURLAction { адрес in обработать(адрес, статья: статья) })
                .environment(\.нажатьПлиткуСтатьи, { плитка in нажатьПлитку(плитка, статья: статья) })
            }
            .onAppear { начать(статья) }
            .onChange(of: прокрутить) { _, цель in
                guard let цель else { return }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    withAnimation(ДвижениеСайта.прокрутка) { прокрутка.scrollTo(цель, anchor: .top) }
                    прокрутить = nil
                }
            }
            .onChange(of: поиск) { _, _ in
                раскрытьНайденное(статья)
            }
        }
    }

    @ViewBuilder
    private func статьяЦеликом(_ статья: СтатьяСайта) -> some View {
        if let первый = статья.первыйЗаголовок, показатьЗаголовок(первый.простой) {
            Text(первый.текст)
                .font(.system(size: размерH1, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
                .id(первый.id)
        }
        if статья.разделы.count >= 3 && !статья.естьКарточки {
            оглавление(статья)
        }
        ForEach(статья.части) { часть in
            if часть.плитки {
                РядПлитокСтатьи(блоки: часть.блоки)
            } else {
                КарточкаСтатьи(блоки: часть.блоки, раскрытые: $раскрытые)
            }
        }
    }

    /// h1 над карточками — если он не повторяет название в шапке.
    private func показатьЗаголовок(_ текст: String) -> Bool {
        let свой = текст.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !свой.isEmpty else { return false }
        return свой.compare(заголовокЭкрана, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame
    }

    /// Оглавление: разделы кнопками-чипами. Лента прокручивается от края до края экрана, чипы — с полями 16, как у
    /// ленты сайта: первый стоит вровень с карточками, последний не упирается в край.
    private func оглавление(_ статья: СтатьяСайта) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(т("toc"))
                .font(.system(size: размерЧипа, weight: .heavy))
                .foregroundStyle(Theme.текстВторой)
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(статья.разделы) { раздел in
                        Button {
                            прокрутить = раздел.id
                        } label: {
                            Text(РазборСтатьи.названиеЧипа(раздел.простой))
                                .font(.system(size: размерЧипа, weight: .semibold))
                                .lineLimit(1)
                                .foregroundStyle(Theme.текстПункта)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Theme.фонПункта, in: Capsule())
                                .overlay { Capsule().strokeBorder(Theme.рамкаПункта, lineWidth: 1) }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 1)
            }
            /* Поля экрана — 16: лента выходит за них, чтобы чипы уезжали под край, а не обрезались посреди. */
            .padding(.horizontal, -16)
        }
    }

    // MARK: Поиск по справке

    /// Блоки, где встречается запрос (вопрос — вместе с ответом), по порядку статьи.
    private func найденное(_ статья: СтатьяСайта) -> [БлокСтатьи] {
        let запрос = запросПоиска
        guard !запрос.isEmpty else { return [] }
        var итог: [БлокСтатьи] = []
        for блок in статья.блоки {
            switch блок.вид {
            case .заголовок, .разделитель, .картинка:
                continue
            default:
                break
            }
            if блок.весьТекст.localizedStandardContains(запрос) {
                итог.append(блок)
            }
        }
        return итог
    }

    @ViewBuilder
    private func найденноеВид(_ статья: СтатьяСайта) -> some View {
        let найдено = найденное(статья)
        if найдено.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                    .accessibilityHidden(true)
                Text(т("nothing_t"))
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .multilineTextAlignment(.center)
                Text(т("nothing_s"))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.текстВторой)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        } else {
            КарточкаСтатьи(блоки: найдено, раскрытые: $раскрытые)
        }
    }

    /// Найденные вопросы — раскрыты: ответ виден сразу. Запрос стёрт — раскрытые поиском свёрнуты.
    private func раскрытьНайденное(_ статья: СтатьяСайта) {
        if запросПоиска.isEmpty {
            раскрытые.subtract(раскрытоПоиском)
            раскрытоПоиском = []
            return
        }
        for блок in найденное(статья) {
            guard case .вопрос = блок.вид, !раскрытые.contains(блок.id) else { continue }
            раскрытые.insert(блок.id)
            раскрытоПоиском.insert(блок.id)
        }
    }

    // MARK: Поддержка

    private var поддержка: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.акцент)
                    .frame(width: 36, height: 36)
                    .background(Theme.мята, in: Circle())
                    .accessibilityHidden(true)
                Text(т("support_s"))
                    .font(.system(size: размерТекста))
                    .foregroundStyle(Theme.текст)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            КнопкаБизнеса(подпись: т("support"), второстепенная: true) { написать() }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1.5)
        }
    }

    // MARK: Якорь и ссылки

    /// Первый показ статьи: раскрыть <details open> и прокрутить к якорю адреса (или открыть его раздел).
    private func начать(_ статья: СтатьяСайта) {
        guard !начатоС else { return }
        начатоС = true
        for блок in статья.блоки {
            if case .вопрос(_, let открыт) = блок.вид, открыт { раскрытые.insert(блок.id) }
        }
        let слова = СтатьяСайта.слова(страница)
        guard !слова.isEmpty else { return }
        if let найдено = статья.переход(слова: слова, название: "", подпись: "", плитка: nil) {
            журнал("адрес " + слова.joined(separator: ","), найдено.1)
            применить(найдено.0, статья: статья)
            return
        }
        /* Сайт отдал ту же страницу разделов (help?sec=start — раздел у него показывает скрипт): раздел по плитке этой
           страницы, что ведёт сюда, — иначе следующий экран повторил бы прежний и нажатие выглядело бы пустым. */
        let свои = Set(слова)
        guard let плитка = статья.блоки.first(where: { блок in
            guard case .карточка(let цель) = блок.вид, let её = СтраницаСайта.из(цель), её.таЖе(страница) else {
                return false
            }
            return !свои.isDisjoint(with: СтатьяСайта.слова(её))
        }) else { return }
        if let найдено = статья.переход(слова: [], название: плитка.простой, подпись: плитка.подпись, плитка: плитка.id) {
            журнал("адрес " + слова.joined(separator: ","), "плитка «\(плитка.простой)»: " + найдено.1)
            применить(найдено.0, статья: статья)
            return
        }
        let вопросы = статья.вопросы(оТеме: плитка.простой, подпись: плитка.подпись)
        журнал("адрес " + слова.joined(separator: ","), "плитка «\(плитка.простой)»: вопросы по словам (\(вопросы.count))")
        применить(.раздел(ОтборРаздела(название: плитка.простой, подпись: плитка.подпись, блоки: вопросы,
                                       откуда: плитка.id)), статья: статья)
    }

    /**
     Плитка раздела. Было: адрес плитки уходил в openURL, а если якоря на странице не было (панель раздела у сайта
     скрыта и показывается скриптом, метка не в id, а в data-cat), нажатие молча гасло. Стало, по порядку:
     (а) механизм сайта — якорь или метка панели; (б) заголовок с названием плитки; (в) раздел на другой странице —
     следующим экраном; (г) вопросы по теме своим видом, а нет их — поиск по справке названием плитки. Пустым нажатие не
     бывает.
     */
    private func нажатьПлитку(_ плитка: БлокСтатьи, статья: СтатьяСайта) {
        guard case .карточка(let свой) = плитка.вид else { return }
        /* Полный адрес: относительный («/kz/ru/help#start») не узнавался страницей справки — нажатие гасло. */
        let адрес = свой.absoluteURL
        let название = плитка.простой
        let страницаАдреса = СтраницаСайта.из(адрес)
        if let чужая = страницаАдреса, !(чужая.таЖе(страница) || (страница.справка && чужая.справка)) {
            журнал(название, "другая страница " + чужая.id)
            перейти(чужая)
            return
        }
        guard let другая = страницаАдреса else {
            /* Не страница справки: как обычная ссылка (сайт, почта, телефон). */
            журнал(название, "адрес " + адрес.absoluteString)
            if РазборСтатьи.оплата(адрес) { return }
            if Config.deepLink(адрес.absoluteURL) != nil {
                if !страница.тарифы { открыть(адрес.absoluteURL) }
            } else if Self.веб(адрес) {
                БезСайта.внешняя(адрес)
            } else if let схема = адрес.scheme, !схема.isEmpty {
                UIApplication.shared.open(адрес)
            } else {
                /* Адрес без схемы открыть нечем — поиск по справке названием плитки, а не пустое нажатие. */
                искать(название)
            }
            return
        }
        if let найдено = статья.переход(слова: СтатьяСайта.слова(другая), название: название,
                                          подпись: плитка.подпись, плитка: плитка.id) {
            журнал(название, найдено.1)
            применить(найдено.0, статья: статья)
            if case .прокрутка(let цель) = найдено.0 { раскрытьПервыйВопрос(после: цель, статья: статья) }
            return
        }
        if !другая.таЖе(страница) {
            журнал(название, "статья справки " + другая.id)
            перейти(другая)
            return
        }
        let вопросы = статья.вопросы(оТеме: название, подпись: плитка.подпись)
        guard !вопросы.isEmpty else {
            /* Раздела нет нигде — поиск по справке названием плитки (как поле поиска сверху). */
            журнал(название, "раздела нет — поиск по названию")
            искать(название)
            return
        }
        журнал(название, "вопросы по словам (\(вопросы.count))")
        применить(.раздел(ОтборРаздела(название: название, подпись: плитка.подпись, блоки: вопросы, откуда: плитка.id)),
                  статья: статья)
    }

    /// Поиск по справке: запрос в поле сверху, найденное — вместо статьи, к началу.
    private func искать(_ запрос: String) {
        let чистый = запрос.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !чистый.isEmpty else { return }
        отбор = nil
        поиск = чистый
        прокрутить = Self.верхПоиска
    }

    /// Как сайт по якорю раздела (hashchange → первый вопрос раскрыт): первый вопрос раздела под заголовком — открыт.
    private func раскрытьПервыйВопрос(после цель: Int, статья: СтатьяСайта) {
        guard let место = статья.блоки.firstIndex(where: { $0.id == цель }),
              case .заголовок = статья.блоки[место].вид else { return }
        var номер = место + 1
        while номер < статья.блоки.count {
            let блок = статья.блоки[номер]
            if case .заголовок = блок.вид { return }
            if case .вопрос = блок.вид {
                раскрытые.insert(блок.id)
                return
            }
            номер += 1
        }
    }

    private func применить(_ переход: ПереходПлитки, статья: СтатьяСайта) {
        поиск = ""
        switch переход {
        case .прокрутка(let цель):
            отбор = nil
            раскрыть(цель, статья: статья)
            прокрутить = цель
        case .раздел(let новый):
            отбор = новый
            прокрутить = Self.верхОтбора
        }
    }

    /// Путь поиска раздела — в журнал отладки (в сборке для App Store его нет).
    private func журнал(_ что: String, _ путь: String) {
        #if DEBUG
        print("[Справка] «\(что)» → \(путь)")
        #endif
    }

    private func обработать(_ адрес: URL, статья: СтатьяСайта) -> OpenURLAction.Result {
        let схема = адрес.scheme?.lowercased() ?? ""
        if схема == "mailto" || схема == "tel" || схема == "sms" { return .systemAction }
        /* Оплата услуг сайта из приложения не открывается (правило App Store 3.1.1). */
        if РазборСтатьи.оплата(адрес) { return .handled }
        if let другая = СтраницаСайта.из(адрес) {
            /* Ссылка на раздел: сначала — раздел этой же страницы (якорь, метка панели, help/start, help?sec=start,
               название плитки с этим адресом); нет его здесь — другая статья справки своим экраном. */
            let рядом = другая.таЖе(страница) || (страница.справка && другая.справка)
            if рядом {
                let строка = адрес.absoluteString
                let плитка = статья.блоки.first(where: { блок in
                    if case .карточка(let цель) = блок.вид { return цель.absoluteString == строка }
                    return false
                })
                if let найдено = статья.переход(слова: СтатьяСайта.слова(другая), название: плитка?.простой ?? "",
                                                  подпись: плитка?.подпись ?? "", плитка: плитка?.id) {
                    журнал(строка, найдено.1)
                    применить(найдено.0, статья: статья)
                    return .handled
                }
            }
            if другая.таЖе(страница) {
                журнал(адрес.absoluteString, "раздела нет на странице")
                /* Не молча: плитка с этим адресом — поиск её названием. */
                if let плитка = статья.блоки.first(where: { блок in
                    if case .карточка(let цель) = блок.вид { return цель.absoluteString == адрес.absoluteString }
                    return false
                }) {
                    искать(плитка.простой)
                }
                return .handled
            }
            перейти(другая)
            return .handled
        }
        if Config.deepLink(адрес.absoluteURL) != nil {
            /* Прочие адреса сайта — окно закрывается, адрес идёт общим путём (свой экран или сайт). */
            if страница.тарифы { return .handled }
            открыть(адрес.absoluteURL)
            return .handled
        }
        /* Чужой сайт (закон на adilet.zan.kz, банк, eGov) — листом Safari внутри приложения, а не уходом в Safari. */
        if Self.веб(адрес) {
            if страница.тарифы { return .handled }
            БезСайта.внешняя(адрес)
            return .handled
        }
        return .systemAction
    }

    /// Адрес страницы в интернете (http/https), а не почта, телефон или другое приложение.
    private static func веб(_ адрес: URL) -> Bool {
        let схема = адрес.scheme?.lowercased() ?? ""
        return схема == "https" || схема == "http"
    }

    /// Якорь внутри вопроса — вопрос раскрыть.
    private func раскрыть(_ цель: Int, статья: СтатьяСайта) {
        for блок in статья.блоки where блок.id == цель {
            if case .вопрос = блок.вид { раскрытые.insert(цель) }
        }
    }

    // MARK: Раздел своим видом

    /// Метка верха раздела (прокрутка к началу): блоки статьи нумеруются с 1.
    private static let верхОтбора = -1
    /// Метка начала найденного (поиск по названию плитки, чей раздел не нашёлся).
    private static let верхПоиска = -2

    /// Раздел, открытый плиткой: «Все разделы», название, подпись и блоки одной карточкой (или «пока нет ответов»).
    private func отборВид(_ отбор: ОтборРаздела) -> some View {
        let ключ = РазборСтатьи.ключРаздела(отбор.название)
        var блоки = отбор.блоки
        /* Заголовок панели, что повторяет название плитки, — уже над карточкой. */
        if let первый = блоки.first, case .заголовок = первый.вид, РазборСтатьи.ключРаздела(первый.простой) == ключ {
            блоки.removeFirst()
        }
        let показать = блоки
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                закрытьОтбор()
            } label: {
                Label(т("all_sections"), systemImage: "chevron.backward")
                    .font(.system(size: размерЧипа + 1, weight: .semibold))
                    .foregroundStyle(Theme.акцент)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)
            .id(Self.верхОтбора)
            VStack(alignment: .leading, spacing: 4) {
                Text(отбор.название)
                    .font(.system(size: размерH1, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if !отбор.подпись.isEmpty {
                    Text(отбор.подпись)
                        .font(.system(size: размерТекста))
                        .foregroundStyle(Theme.текстВторой)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 4)
            if показать.isEmpty {
                Text(т("section_empty"))
                    .font(.system(size: размерТекста))
                    .foregroundStyle(Theme.текстВторой)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(16)
                    .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                            .strokeBorder(Theme.линия, lineWidth: 1.5)
                    }
            } else {
                КарточкаСтатьи(блоки: показать, раскрытые: $раскрытые)
            }
        }
    }

    /// Назад ко всем разделам — к плитке, откуда пришли.
    private func закрытьОтбор() {
        let откуда = отбор?.откуда
        отбор = nil
        if let откуда { прокрутить = откуда }
    }
}
