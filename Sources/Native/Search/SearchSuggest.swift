import Foundation
import WebKit

/**
 ПОДСКАЗКИ ПОИСКА КАК НА САЙТЕ (владелец 26.09.2026, TestFlight 1.10: «поисковик не такой же как на сайте — нужно чтобы
 такой же с подсказкой»).

 У сайта подсказки считаются в браузере, без запроса к серверу и без задержки: на каждый ввод в #mk-sov-inp (и в #mk-q
 на широком экране) mkSovRender строит список заново (js/marketplace.min.js). Здесь — то же самое, теми же правилами:
 • пустое поле — «Вы искали» (localStorage mk_recent, до 6 строк, «Очистить», «×» у строки) и «Популярные запросы»
   (MK_TRENDS, до 10; запрос, совпавший с названием раздела, — строкой раздела);
 • набрано — первой строкой сам запрос (лупа), «Категории» (mkSovCatMatch, до 5), «Бренды» (mkSovBrandMatch, до 6),
   затем умные подсказки (mkSmartSuggest: по загруженным объявлениям и таблице MK_SUGG, до 7, набранное — обычным
   шрифтом, дописанное — жирным) и прежние запросы с популярными, где есть все слова запроса (до 6, совпадение жирным).
 Сравнение — по «канону» mkCanon: латиница вместо кириллицы и одно имя бренда («айфон» = «iphone»).

 Разделы сайта (MK_CFLAT: имя на языке страницы, родитель, краска, бренды) и MK_TRENDS берём у загруженной страницы
 сайта; страница не та или не загрузилась — сами качаем тот же справочник /js/cats-<язык>.js (MK_CATS), а популярные —
 запасные из ПоискСайтаText.
 */
enum ПодсказкиСайта {

    // MARK: - Итог

    /// Раздел в подсказках (строка .mk-sov-catrow): ключ, имя, путь «Родитель › …», краска раздела.
    struct Раздел: Hashable {
        let ключ: String
        let имя: String
        let путь: String
        let краска: String
    }

    /// Бренд в подсказках: имя, раздел, где он есть, название раздела и краска.
    struct Бренд: Hashable {
        let имя: String
        let раздел: String
        let имяРаздела: String
        let краска: String
    }

    enum ВидСтроки: Hashable {
        /// Сам набранный запрос — лупа, без кнопки справа.
        case запрос
        /// Умная подсказка — лупа, «вставить» справа, дописанное жирным.
        case подсказка
        /// Прежний или популярный запрос в наборе — стрелка тренда, «вставить» справа, совпадение жирным.
        case тренд
        /// «Вы искали» у пустого поля — часы, «×» справа.
        case недавний
    }

    struct Строка: Hashable {
        let текст: String
        let вид: ВидСтроки
        /// Жирная часть: от и до — в символах текста; nil — без выделения.
        let жирно: Range<Int>?
    }

    /// Популярный запрос у пустого поля: строкой раздела, если совпал с его названием, иначе строкой тренда.
    enum Популярный: Hashable {
        case раздел(Раздел)
        case запрос(Строка)
    }

    struct Выдача {
        var набрано = ""
        var разделы: [Раздел] = []
        var бренды: [Бренд] = []
        /// Первая строка (сам запрос), подсказки и тренды — одним списком, как .mk-sov-list сайта.
        var запрос: Строка? = nil
        var строки: [Строка] = []
        var недавние: [Строка] = []
        var популярные: [Популярный] = []
    }

    /// mkSovRender: что показать под полем. недавние — mk_recent (новые сверху), товары — загруженная лента (MK сайта).
    static func выдача(_ ввод: String, каталог: КаталогПоиска, недавние: [String], товары: [Listing]) -> Выдача {
        var итог = Выдача()
        let t = ввод.trimmingCharacters(in: .whitespacesAndNewlines)
        итог.набрано = t
        if t.isEmpty {
            итог.недавние = недавние.prefix(6).map { Строка(текст: $0, вид: .недавний, жирно: nil) }
            итог.популярные = каталог.популярные.prefix(10).compactMap { популярный($0, каталог: каталог) }
            return итог
        }
        итог.запрос = Строка(текст: t, вид: .запрос, жирно: nil)
        итог.разделы = разделы(t, каталог: каталог)
        итог.бренды = бренды(t, каталог: каталог)
        let умные = умныеПодсказки(t, товары: товары)
        var взятые = Set(умные.map { $0.lowercased() })
        let s = канон(t)
        let слова = s.split(separator: " ").map(String.init)
        var прочие: [String] = []
        for запрос in недавние + каталог.популярные {
            let нижний = запрос.lowercased()
            let n = канон(запрос)
            let подходит = !слова.isEmpty && n != s && слова.allSatisfy { n.contains($0) }
            guard подходит, !взятые.contains(нижний) else { continue }
            взятые.insert(нижний)
            прочие.append(запрос)
        }
        var строки: [Строка] = []
        for подсказка in умные {
            строки.append(Строка(текст: подсказка, вид: .подсказка, жирно: дописанное(подсказка, набрано: t)))
        }
        for запрос in прочие.prefix(6) {
            строки.append(Строка(текст: запрос, вид: .тренд, жирно: совпадение(запрос, с: t)))
        }
        итог.строки = строки
        return итог
    }

    /// _mkSovTrendRow: популярный запрос, совпавший с названием раздела, — строкой раздела.
    private static func популярный(_ запрос: String, каталог: КаталогПоиска) -> Популярный? {
        let e = запрос.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !e.isEmpty else { return nil }
        let нижний = e.lowercased()
        if let раздел = разделы(e, каталог: каталог).first(where: {
            $0.имя.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == нижний
        }) {
            return .раздел(раздел)
        }
        return .запрос(Строка(текст: e, вид: .тренд, жирно: nil))
    }

    /// Строка подсказки: набранное — начало (без учёта регистра) и короче — дописанное жирным.
    private static func дописанное(_ текст: String, набрано: String) -> Range<Int>? {
        let длина = набрано.count
        guard длина < текст.count, текст.lowercased().hasPrefix(набрано.lowercased()) else { return nil }
        return длина..<текст.count
    }

    /// Строка тренда: первое вхождение набранного — жирным.
    private static func совпадение(_ текст: String, с набрано: String) -> Range<Int>? {
        let нижний = текст.lowercased()
        guard !набрано.isEmpty, let место = нижний.range(of: набрано.lowercased()) else { return nil }
        let начало = нижний.distance(from: нижний.startIndex, to: место.lowerBound)
        let конец = начало + нижний.distance(from: место.lowerBound, to: место.upperBound)
        guard конец <= текст.count else { return nil }
        return начало..<конец
    }

    // MARK: - Разделы и бренды (mkSovCatMatch, mkSovBrandMatch)

    /// Краски корней разделов — MK_CAT_COLOR (js/mk-refs-ru.js).
    static let краскиКорней: [String: String] = [
        "electronics": "#2563EB", "transport": "#DC2626", "realty": "#059669", "clothing": "#DB2777",
        "home-garden": "#D97706", "kids": "#FACC15", "sport": "#0891B2", "animals": "#7C3AED", "jobs": "#4F46E5",
        "services": "#0D9488", "hobby": "#C026D3", "food-farm": "#65A30D", "beauty": "#E11D48"
    ]

    static func разделы(_ ввод: String, каталог: КаталогПоиска) -> [Раздел] {
        let e = ввод.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard e.count >= 2 else { return [] }
        let n = канон(e)
        var найдено: [Раздел] = []
        for ключ in каталог.порядок {
            if найдено.count >= 5 { break }
            guard let узел = каталог.узлы[ключ] else { continue }
            let a = узел.нижнее
            let s = узел.канонИмени
            let поИмени = !a.isEmpty && (a.contains(e) || e.contains(a))
            let поКанону = !n.isEmpty && !s.isEmpty && (s.contains(n) || n.contains(s))
            guard поИмени || поКанону else { continue }
            let корень = каталог.корень(ключ)
            let краска = каталог.краски[ключ] ?? каталог.краски[корень] ?? "#0F5132"
            найдено.append(Раздел(ключ: ключ, имя: узел.имя, путь: каталог.путь(ключ), краска: краска))
        }
        let длина = ввод.count
        return устойчиво(найдено) { abs($0.имя.count - длина) }.prefix(5).map { $0 }
    }

    static func бренды(_ ввод: String, каталог: КаталогПоиска) -> [Бренд] {
        let e = ввод.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard e.count >= 2 else { return [] }
        var найдено: [Бренд] = []
        for ключ in каталог.брендыПорядок {
            if найдено.count >= 6 { break }
            guard ключ.contains(e) || e.contains(ключ), let запись = каталог.бренды[ключ],
                  let раздел = запись.разделы.first else { continue }
            let имяРаздела = каталог.узлы[раздел]?.имя ?? раздел
            let краска = каталог.краски[раздел] ?? каталог.узлы[раздел]?.краска ?? "#0F5132"
            найдено.append(Бренд(имя: запись.имя, раздел: раздел, имяРаздела: имяРаздела, краска: краска))
        }
        let длина = ввод.count
        return устойчиво(найдено) { abs($0.имя.count - длина) }.prefix(6).map { $0 }
    }

    /// Сортировка без перестановки равных — как Array.prototype.sort браузера.
    private static func устойчиво<T>(_ список: [T], ключ: (T) -> Int) -> [T] {
        список.enumerated()
            .sorted { a, b in
                let ka = ключ(a.element)
                let kb = ключ(b.element)
                return ka != kb ? ka < kb : a.offset < b.offset
            }
            .map { $0.element }
    }

    // MARK: - Канон (mkCanon)

    /// _MK_ALIAS: первое слово — каноническое имя.
    private static let псевдонимы: [[String]] = [
        ["iphone", "айфон", "айфона", "айфоны", "apple", "эпл", "эппл"], ["samsung", "самсунг", "самсунга"],
        ["xiaomi", "ксиоми", "сяоми", "ксяоми"], ["redmi", "редми"], ["huawei", "хуавей", "хуавэй"], ["honor", "хонор"],
        ["asus", "асус"], ["lenovo", "леново"], ["acer", "асер", "эйсер"], ["dell", "делл"],
        ["macbook", "макбук", "макбука"], ["msi", "мси"], ["core", "коре", "кор"], ["ryzen", "райзен", "ризен"],
        ["intel", "интел"], ["amd", "амд"], ["nvidia", "нвидиа"], ["toyota", "тойота"], ["kia", "киа"],
        ["hyundai", "хендай", "хёндай", "хундай"], ["mercedes", "мерседес", "мерс"], ["bmw", "бмв", "бэха"],
        ["lexus", "лексус"], ["nissan", "ниссан", "нисан"], ["volkswagen", "фольксваген"], ["nike", "найк"],
        ["adidas", "адидас"], ["puma", "пума"], ["playstation", "плейстейшн", "плейстешн", "плойка"],
        ["xbox", "иксбокс", "хбокс"], ["nintendo", "нинтендо"], ["lg", "лджи", "элджи"], ["sony", "сони"],
        ["bosch", "бош"], ["canon", "кэнон", "канон"], ["nikon", "никон"],
        ["airpods", "эирподс", "аирподс", "эйрподс"], ["ipad", "айпад"]
    ]

    private static let картаПсевдонимов: [String: String] = {
        var карта: [String: String] = [:]
        for группа in псевдонимы {
            guard let главное = группа.first else { continue }
            for слово in группа { карта[слово] = главное }
        }
        return карта
    }()

    /// _MK_SPECWORD — не бренды, а слова характеристик.
    private static let словаХарактеристик: Set<String> = ["core", "ryzen", "intel", "amd", "nvidia"]

    /// _MK_BRANDS.
    private static let канонБрендов: Set<String> = {
        var набор = Set<String>()
        for группа in псевдонимы {
            if let главное = группа.first, !словаХарактеристик.contains(главное) { набор.insert(главное) }
        }
        return набор
    }()

    private static let двойные: [Character: String] = [
        "ж": "zh", "ч": "ch", "ш": "sh", "щ": "sch", "ю": "yu", "я": "ya", "ё": "e", "ц": "ts", "х": "h"
    ]

    private static let одинарные: [Character: String] = [
        "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "з": "z", "и": "i", "й": "y", "к": "k", "л": "l",
        "м": "m", "н": "n", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t", "у": "u", "ф": "f", "ъ": "", "ы": "y",
        "ь": "", "э": "e"
    ]

    /// Буква слова для замены псевдонимом: [a-zа-яё0-9-].
    private static func букваСлова(_ символ: Character) -> Bool {
        guard символ.unicodeScalars.count == 1, let код = символ.unicodeScalars.first?.value else { return false }
        return (код >= 0x61 && код <= 0x7A) || (код >= 0x30 && код <= 0x39) || код == 0x2D
            || (код >= 0x430 && код <= 0x44F) || код == 0x451
    }

    private static func латиницаИлиЦифра(_ символ: Character) -> Bool {
        guard символ.unicodeScalars.count == 1, let код = символ.unicodeScalars.first?.value else { return false }
        return (код >= 0x61 && код <= 0x7A) || (код >= 0x30 && код <= 0x39)
    }

    /// mkCanon: нижний регистр → псевдонимы брендов → латиница → только [a-z0-9] словами через один пробел.
    static func канон(_ исходный: String) -> String {
        let нижний = исходный.lowercased()
        var собранное = ""
        var слово = ""
        for символ in нижний {
            if букваСлова(символ) {
                слово.append(символ)
            } else {
                if !слово.isEmpty {
                    собранное += картаПсевдонимов[слово] ?? слово
                    слово = ""
                }
                собранное.append(символ)
            }
        }
        if !слово.isEmpty { собранное += картаПсевдонимов[слово] ?? слово }
        var латиница = ""
        for символ in собранное {
            if let замена = двойные[символ] {
                латиница += замена
            } else if let замена = одинарные[символ] {
                латиница += замена
            } else {
                латиница.append(символ)
            }
        }
        var чистое = ""
        for символ in латиница {
            чистое.append(латиницаИлиЦифра(символ) ? символ : " ")
        }
        return чистое.split(separator: " ").joined(separator: " ")
    }

    // MARK: - Умные подсказки (mkSmartSuggest, mkDataSuggest)

    /// Запись MK_SUGG: bo — только бренд (ищется, если общего слова нет), trig — слова запуска.
    private struct Схема {
        let толькоБренд: Bool
        let запуск: [String]
        let бренды: [String]
        let характеристики: [String]
        let запускК: [String]
        let брендыК: [String]
        let характеристикиК: [String]

        init(_ толькоБренд: Bool, _ запуск: [String], _ бренды: [String], _ характеристики: [String]) {
            self.толькоБренд = толькоБренд
            self.запуск = запуск
            self.бренды = бренды
            self.характеристики = характеристики
            запускК = запуск.map { ПодсказкиСайта.канон($0) }
            брендыК = бренды.map { ПодсказкиСайта.канон($0) }
            характеристикиК = характеристики.map { ПодсказкиСайта.канон($0) }
        }
    }

    /// MK_SUGG сайта — в том же порядке.
    private static let схемы: [Схема] = [
        Схема(true, ["toyota", "тойота"], ["Camry", "Corolla", "RAV4", "Land Cruiser", "Prado", "Highlander"],
              ["2020", "2021", "2022", "автомат", "дизель", "с пробегом"]),
        Схема(true, ["kia", "киа"], ["K5", "Rio", "Sportage", "Sorento", "Cerato", "Seltos"],
              ["2021", "2022", "автомат", "с пробегом"]),
        Схема(true, ["hyundai", "хендай", "хёндай"], ["Elantra", "Sonata", "Tucson", "Accent", "Santa Fe", "Creta"],
              ["2021", "2022", "автомат", "с пробегом"]),
        Схема(true, ["iphone", "айфон", "айфона"], ["15 Pro Max", "15 Pro", "15", "14 Pro", "14", "13", "12", "11", "SE"],
              ["128 ГБ", "256 ГБ", "512 ГБ", "новый", "б/у", "на гарантии"]),
        Схема(true, ["samsung", "самсунг"],
              ["Galaxy S24 Ultra", "Galaxy S24", "Galaxy S23", "Galaxy A55", "Galaxy A35", "Galaxy Z Flip"],
              ["128 ГБ", "256 ГБ", "новый", "б/у"]),
        Схема(true, ["xiaomi", "ксиоми", "сяоми", "редми", "redmi"],
              ["Redmi Note 13", "Redmi Note 12", "13 Pro", "14", "Poco X6"], ["128 ГБ", "256 ГБ", "новый"]),
        Схема(false, ["ноутбук", "ноутбуки", "ноут", "laptop"],
              ["ASUS", "Lenovo", "HP", "Acer", "Dell", "MacBook", "MSI", "Huawei"],
              ["игровой", "Intel Core i5", "Intel Core i7", "Ryzen 5", "Ryzen 7", "16 ГБ ОЗУ", "SSD 512 ГБ", "RTX 4060",
               "для работы"]),
        Схема(false, ["телефон", "смартфон", "смарт", "телефона"],
              ["iPhone", "Samsung Galaxy", "Xiaomi", "Honor", "Realme", "Tecno"],
              ["128 ГБ", "256 ГБ", "новый", "б/у", "на гарантии"]),
        Схема(false, ["планшет", "ipad", "tablet"],
              ["iPad", "iPad Air", "iPad Pro", "Samsung Galaxy Tab", "Xiaomi Pad", "Huawei MatePad"],
              ["128 ГБ", "256 ГБ", "с клавиатурой", "для ребёнка"]),
        Схема(false, ["телевизор", "телевизора", "televizor"], ["Samsung", "LG", "Xiaomi", "Sony", "Haier", "Artel"],
              ["4K", "Smart TV", "43 дюйма", "50 дюймов", "55 дюймов", "65 дюймов"]),
        Схема(false, ["наушники"], ["AirPods", "JBL", "Sony", "Samsung", "Marshall", "Xiaomi"],
              ["беспроводные", "с шумоподавлением", "игровые"]),
        Схема(false, ["часы", "watch"], ["Apple Watch", "Samsung Galaxy Watch", "Xiaomi", "Amazfit", "Garmin"],
              ["смарт", "мужские", "женские"]),
        Схема(false, ["приставка", "playstation", "xbox", "консоль"],
              ["PlayStation 5", "PlayStation 4", "Xbox Series X", "Xbox Series S", "Nintendo Switch"],
              ["с играми", "новая", "б/у"]),
        Схема(false, ["холодильник", "холодильника"], ["LG", "Samsung", "Bosch", "Atlant", "Beko", "Haier"],
              ["двухкамерный", "No Frost", "Side by Side", "большой"]),
        Схема(false, ["стиральная", "стиралка", "стиральную"], ["LG", "Samsung", "Bosch", "Indesit", "Atlant", "Beko"],
              ["автомат", "узкая", "с сушкой"]),
        Схема(false, ["диван", "дивана"], ["угловой", "прямой", "раскладной", "модульный", "еврокнижка"],
              ["новый", "б/у", "с доставкой", "кожаный"]),
        Схема(false, ["кровать", "шкаф", "мебель"], ["двуспальная", "односпальная", "шкаф-купе", "комод", "стол"],
              ["новая", "б/у", "с доставкой"]),
        Схема(false, ["велосипед", "велик"], ["Trek", "Giant", "Stels", "Forward", "Merida"],
              ["горный", "детский", "скоростной", "складной", "взрослый"]),
        Схема(false, ["кроссовки", "кеды", "обувь"], ["Nike", "Adidas", "Puma", "New Balance", "Reebok", "Asics"],
              ["мужские", "женские", "детские", "оригинал", "42 размер", "43 размер"]),
        Схема(false, ["коляска", "коляску", "коляски"], ["2 в 1", "3 в 1", "прогулочная", "трансформер"],
              ["для новорождённых", "лёгкая", "зимняя", "с доставкой"]),
        Схема(false, ["квартира", "квартиру", "квартиры", "снять", "аренда"],
              ["1-комнатная", "2-комнатная", "3-комнатная", "студия"],
              ["посуточно", "на длительный срок", "с мебелью", "от собственника", "в новостройке"]),
        Схема(false, ["машина", "машину", "авто", "автомобиль", "автомобили"],
              ["Toyota", "Kia", "Hyundai", "Mercedes", "BMW", "Volkswagen", "Lexus", "Nissan"],
              ["2020", "2021", "2022", "автомат", "механика", "дизель", "бензин", "седан", "кроссовер", "с пробегом"])
    ]

    /// _MK_STOP.
    private static let стоп: Set<String> = [
        "i", "v", "na", "s", "so", "dlya", "po", "ot", "do", "za", "k", "o", "ob", "iz", "u", "ili", "a", "the", "of",
        "for", "with", "and", "or", "no", "b", "bu", "new", "used", "prodam", "prodayu", "prodaetsya", "srochno", "torg",
        "cena", "tenge", "tg", "kzt", "novyy", "novaya", "novoe", "noviy", "sostoyanie", "otlichnoe", "horoshee",
        "ideal", "idealnoe", "ochen", "est"
    ]

    private static func выражение(_ шаблон: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: шаблон, options: [])
    }

    private static let единицыВТексте = выражение("\\b(gb|tb|mb|ozu|dyuym[a-z]*|ghz|mhz)\\b")
    private static let единицаСловом = выражение("^(gb|tb|mb|ozu|dyuym[a-z]*|ghz|mhz)$")
    private static let единицаДанных = выражение("^(gb|tb|mb|ghz|mhz|dyuym[a-z]*)$")
    private static let единицаЗаголовка = try? NSRegularExpression(pattern: "^(гб|gb|тб|tb|мб|mb|гц|ghz|мгц|mhz|дюйм[а-я]*)$",
                                                                   options: [.caseInsensitive])
    private static let число = выражение("^\\d+([.,]\\d+)?$")
    private static let год = выражение("^\\d{4}$")
    private static let годВТексте = выражение("\\b\\d{4}\\b")

    private static func совпало(_ выражение: NSRegularExpression?, _ текст: String) -> Bool {
        guard let выражение else { return false }
        return выражение.firstMatch(in: текст, options: [], range: NSRange(текст.startIndex..., in: текст)) != nil
    }

    private static func всеСовпадения(_ выражение: NSRegularExpression?, _ текст: String) -> [String] {
        guard let выражение else { return [] }
        let совпадения = выражение.matches(in: текст, options: [], range: NSRange(текст.startIndex..., in: текст))
        return совпадения.compactMap { совпадение in
            Range(совпадение.range, in: текст).map { String(текст[$0]) }
        }
    }

    /// e.replace(/\s*\S+$/, "") — без последнего слова.
    private static func безПоследнегоСлова(_ текст: String) -> String {
        текст.replacingOccurrences(of: "\\s*\\S+$", with: "", options: .regularExpression)
    }

    private static func слова(_ текст: String) -> [String] {
        текст.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// Каноны объявлений — _mkItemCanon кэширует их в самом объявлении (__ch); здесь — по номеру.
    /// Только с главной нити: подсказки считает вид поиска.
    private static var канонТоваров: [String: String] = [:]

    private static func канонТовара(_ товар: Listing) -> String {
        if let готовый = канонТоваров[товар.id] { return готовый }
        let готовый = канон(товар.title + " " + (товар.описание ?? ""))
        if канонТоваров.count > 3000 { канонТоваров.removeAll() }
        канонТоваров[товар.id] = готовый
        return готовый
    }

    /// _mkTitleToks: слова заголовка; число с единицей («256 ГБ») — одним словом.
    private static func словаЗаголовка(_ заголовок: String) -> [String] {
        let части = заголовок.split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == "/" || $0 == "|" })
            .map(String.init)
        var итог: [String] = []
        var i = 0
        while i < части.count {
            if i + 1 < части.count, совпало(число, части[i]), совпало(единицаЗаголовка, части[i + 1]) {
                итог.append(части[i] + " " + части[i + 1])
                i += 2
            } else {
                итог.append(части[i])
                i += 1
            }
        }
        return итог
    }

    /// Ключи объекта в порядке Object.keys: сначала целые числа по возрастанию, затем остальные — в порядке появления.
    private static func порядокКлючей(_ ключи: [String]) -> [String] {
        var числа: [(Int, String)] = []
        var прочие: [String] = []
        for ключ in ключи {
            if let n = Int(ключ), n >= 0, String(n) == ключ, n < 4_294_967_295 {
                числа.append((n, ключ))
            } else {
                прочие.append(ключ)
            }
        }
        return числа.sorted { $0.0 < $1.0 }.map { $0.1 } + прочие
    }

    /// mkDataSuggest: дописать запрос словами заголовков загруженных объявлений, где есть все слова запроса.
    private static func поДанным(канонЗапроса: String, слова o: [String], набрано: String,
                                 естьУже: (String) -> Bool, товары: [Listing]) -> [String] {
        guard !товары.isEmpty else { return [] }
        let словаНабора = слова(набрано)
        var счёт: [String: Int] = [:]
        var показ: [String: String] = [:]
        var появление: [String] = []
        var мерило = 0
        for товар in товары {
            if мерило >= 600 { break }
            let u = канонТовара(товар)
            guard o.allSatisfy({ u.contains($0) }) else { continue }
            мерило += 1
            for часть in словаЗаголовка(товар.title) {
                let т = часть.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !т.isEmpty else { continue }
                let к = канон(т)
                if к.isEmpty || к.count < 2 || стоп.contains(к) || совпало(единицаДанных, к) || o.contains(к)
                    || естьУже(к) {
                    continue
                }
                if счёт[к] == nil {
                    счёт[к] = 0
                    показ[к] = т
                    появление.append(к)
                }
                счёт[к, default: 0] += 1
            }
        }
        let ключи = порядокКлючей(появление)
        guard !ключи.isEmpty else { return [] }
        let порядок = ключи.enumerated()
            .sorted { a, b in
                let ca = счёт[a.element] ?? 0
                let cb = счёт[b.element] ?? 0
                return ca != cb ? ca > cb : a.offset < b.offset
            }
            .map { $0.element }
        if let p = o.last, p.count >= 2, let первая = p.first, !первая.isNumber {
            let начатые = порядок.filter { $0 != p && $0.hasPrefix(p) }
            if !начатые.isEmpty {
                let v = безПоследнегоСлова(набрано)
                return начатые.prefix(8).map { (v.isEmpty ? "" : v + " ") + (показ[$0] ?? $0) }
            }
        }
        if словаНабора.count >= 4 { return [] }
        return порядок.prefix(8)
            .map { набрано + " " + (показ[$0] ?? $0) }
            .filter { слова($0).count <= 4 }
    }

    /// mkSmartSuggest: до 7 подсказок, без повторов по канону.
    static func умныеПодсказки(_ ввод: String, товары: [Listing]) -> [String] {
        let e = ввод.trimmingCharacters(in: .whitespacesAndNewlines)
        guard e.count >= 2 else { return [] }
        let n = канон(e)
        guard !n.isEmpty else { return [] }
        let o = n.split(separator: " ").map(String.init)
        let брендЕсть = o.contains { канонБрендов.contains($0) }
        let вЗапросе = " " + n + " "
        func есть(_ т: String) -> Bool { !т.isEmpty && вЗапросе.contains(" " + т + " ") }
        func естьУже(_ т: String) -> Bool {
            if есть(т) { return true }
            if ПодсказкиСайта.совпало(ПодсказкиСайта.год, т) && ПодсказкиСайта.совпало(ПодсказкиСайта.годВТексте, n) {
                return true
            }
            for единица in ПодсказкиСайта.всеСовпадения(ПодсказкиСайта.единицыВТексте, т)
            where вЗапросе.contains(" " + единица + " ") {
                return true
            }
            return false
        }
        let сДанных = поДанным(канонЗапроса: n, слова: o, набрано: e, естьУже: естьУже, товары: товары)
        func подходит(_ схема: Схема) -> Bool {
            схема.запускК.contains { запуск in
                o.contains { слово in слово == запуск || слово.hasPrefix(запуск) || запуск.hasPrefix(слово) }
            }
        }
        let общая = схемы.first(where: { !$0.толькоБренд && подходит($0) })
        let схема = общая ?? схемы.first(where: { $0.толькоБренд && подходит($0) })
        var u: [String] = []
        if let схема, let b = o.last {
            let брендУже = брендЕсть || схема.брендыК.contains { есть($0) }
            let g = брендУже ? схема.характеристики : схема.бренды + схема.характеристики
            let y = брендУже ? схема.характеристикиК : схема.брендыК + схема.характеристикиК
            let последнееЗапуск = схема.запускК.contains { запуск in
                b == запуск || b.hasPrefix(запуск) || запуск.hasPrefix(b)
            }
            let последнееЕдиница = совпало(единицаСловом, b)
            if !последнееЗапуск && !последнееЕдиница && b.count >= 2 {
                let m = безПоследнегоСлова(e)
                for (i, вариант) in g.enumerated() where i < y.count {
                    let к = y[i]
                    if !к.isEmpty && !естьУже(к) && (" " + к).contains(" " + b) {
                        u.append((m.isEmpty ? "" : m + " ") + вариант)
                    }
                }
            }
            if u.isEmpty && слова(e).count < 4 {
                for (i, вариант) in g.enumerated() where i < y.count && !естьУже(y[i]) {
                    let строка = e + " " + вариант
                    if слова(строка).count <= 4 { u.append(строка) }
                }
            }
        }
        var виденные = Set<String>()
        var итог: [String] = []
        for вариант in сДанных + u {
            let к = канон(вариант)
            guard !к.isEmpty, !виденные.contains(к) else { continue }
            виденные.insert(к)
            итог.append(вариант)
        }
        return Array(итог.prefix(7))
    }
}

// MARK: - Справочник разделов

/// MK_CFLAT и MK_TRENDS сайта: разделы в порядке дерева (обход сверху вниз, как строит MK_CFLAT страница).
struct КаталогПоиска {
    struct Узел {
        let имя: String
        let родитель: String?
        let краска: String
        let бренды: [String]
        /// Имя в нижнем регистре и его канон — считаются один раз, при добавлении.
        var нижнее = ""
        var канонИмени = ""
    }

    struct ЗаписьБренда {
        let имя: String
        var разделы: [String]
    }

    var порядок: [String] = []
    var узлы: [String: Узел] = [:]
    var популярные: [String] = ПоискСайтаText.популярные
    /// MK_CAT_COLOR.
    var краски: [String: String] = ПодсказкиСайта.краскиКорней
    /// mkBrandIndex: бренд в нижнем регистре → имя и разделы; порядок — как ключи объекта сайта.
    private(set) var бренды: [String: ЗаписьБренда] = [:]
    private(set) var брендыПорядок: [String] = []

    var пустой: Bool { порядок.isEmpty }

    mutating func добавить(_ ключ: String, _ узел: Узел) {
        guard !ключ.isEmpty, узлы[ключ] == nil else { return }
        var готовый = узел
        готовый.нижнее = узел.имя.lowercased()
        готовый.канонИмени = ПодсказкиСайта.канон(готовый.нижнее)
        порядок.append(ключ)
        узлы[ключ] = готовый
    }

    mutating func собратьБренды() {
        бренды = [:]
        брендыПорядок = []
        for ключ in порядок {
            guard let узел = узлы[ключ] else { continue }
            for бренд in узел.бренды {
                let нижний = бренд.lowercased()
                if бренды[нижний] == nil {
                    бренды[нижний] = ЗаписьБренда(имя: бренд, разделы: [])
                    брендыПорядок.append(нижний)
                }
                бренды[нижний]?.разделы.append(ключ)
            }
        }
    }

    func корень(_ ключ: String) -> String {
        var текущий = ключ
        var шаги = 0
        while let родитель = узлы[текущий]?.родитель, шаги < 12 {
            текущий = родитель
            шаги += 1
        }
        return текущий
    }

    /// Путь для строки раздела: предки от корня через « › », без самого раздела.
    func путь(_ ключ: String) -> String {
        var имена: [String] = []
        var текущий: String? = ключ
        var шаги = 0
        while let т = текущий, шаги < 12 {
            имена.insert(узлы[т]?.имя ?? т, at: 0)
            текущий = узлы[т]?.родитель
            шаги += 1
        }
        if !имена.isEmpty { имена.removeLast() }
        return имена.joined(separator: " › ")
    }
}

/// Загрузка справочника раз за запуск: у страницы сайта, иначе /js/cats-<язык>.js.
@MainActor
enum ЗагрузкаКаталогаПоиска {
    private static var готовый: КаталогПоиска? = nil
    private static var идёт: Task<КаталогПоиска, Never>? = nil
    /// Поколение справочника: сменили язык — загрузка, начатая на прежнем, свой ответ уже не запоминает.
    private static var поколение = 0

    static var сейчас: КаталогПоиска? { готовый }

    /// Сменили язык приложения (ЯзыкПриложения.выбрать): справочник на прежнем — забыть; следующий запрос возьмёт новый.
    static func забыть() {
        поколение += 1
        готовый = nil
        идёт = nil
    }

    /**
     Имя раздела на языке приложения из справочника сайта (cats-<язык>.js); справочника ещё нет или раздела в нём нет —
     nil, и экран остаётся при своём (снимок главной, слова приложения, ключ).
     */
    static func имя(_ ключ: String) -> String? {
        guard let имя = готовый?.узлы[ключ]?.имя, !имя.isEmpty else { return nil }
        return имя
    }

    static func получить() async -> КаталогПоиска {
        if let готовый { return готовый }
        if let идёт { return await идёт.value }
        let своё = поколение
        let задача = Task { @MainActor () -> КаталогПоиска in
            var каталог = await соСтраницы() ?? КаталогПоиска()
            if каталог.пустой, let скачанный = await скачать() {
                let популярные = каталог.популярные
                каталог = скачанный
                каталог.популярные = популярные
            }
            каталог.собратьБренды()
            return каталог
        }
        идёт = задача
        let каталог = await задача.value
        /* Пока качали, сменили язык (забыть) — этот справочник на прежнем языке: отдать спросившему, но не запоминать. */
        guard своё == поколение else { return каталог }
        идёт = nil
        /* Пустой (нет сети, страница не та) не запоминаем — следующее открытие поиска попробует снова. */
        if !каталог.пустой { готовый = каталог }
        return каталог
    }

    /// MK_CFLAT, MK_TRENDS и MK_CAT_COLOR загруженной страницы — на её языке и ровно те, что у сайта.
    private static func соСтраницы() async -> КаталогПоиска? {
        guard let web = WebBridge.shared.webView, WebBridge.shared.isLoaded else { return nil }
        let js = "(function(){try{var F=(typeof MK_CFLAT!=='undefined'&&MK_CFLAT)?MK_CFLAT:{};"
            + "var T=(typeof MK_TRENDS!=='undefined'&&MK_TRENDS)?MK_TRENDS:[];"
            + "var C=(typeof MK_CAT_COLOR!=='undefined'&&MK_CAT_COLOR)?MK_CAT_COLOR:{};var r=[];"
            + "Object.keys(F).forEach(function(k){var n=F[k]||{};r.push([k,String(n.name||''),String(n.parent||''),"
            + "String(n.color||''),(n.brands||[]).map(String)]);});"
            + "return JSON.stringify({c:r,t:T.map(String),k:C});}catch(e){return '{}';}})()"
        guard let строка = try? await web.evaluateJavaScript(js) as? String,
              let данные = строка.data(using: .utf8),
              let ответ = (try? JSONSerialization.jsonObject(with: данные)) as? [String: Any] else { return nil }
        var каталог = КаталогПоиска()
        if let популярные = ответ["t"] as? [String], !популярные.isEmpty { каталог.популярные = популярные }
        if let краски = ответ["k"] as? [String: String], !краски.isEmpty {
            каталог.краски.merge(краски) { _, новая in новая }
        }
        for запись in (ответ["c"] as? [[Any]]) ?? [] {
            guard запись.count >= 5, let ключ = запись[0] as? String else { continue }
            let имя = (запись[1] as? String) ?? ""
            let родитель = (запись[2] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let краска = (запись[3] as? String) ?? ""
            let бренды = (запись[4] as? [String]) ?? []
            каталог.добавить(ключ, КаталогПоиска.Узел(имя: имя, родитель: родитель, краска: краска, бренды: бренды))
        }
        return каталог
    }

    /// Тот же справочник, что грузит страница: /js/cats-<язык>.js — «var MK_CATS=[…];» с деревом разделов.
    private static func скачать() async -> КаталогПоиска? {
        let язык = ЯзыкПриложения.shared.текущий.сайт
        var адреса: [URL] = []
        if let свой = Config.url("/js/cats-" + язык + ".js") { адреса.append(свой) }
        if язык != "ru", let русский = Config.url("/js/cats-ru.js") { адреса.append(русский) }
        for адрес in адреса {
            var запрос = URLRequest(url: адрес)
            запрос.timeoutInterval = 20
            guard let пара = try? await URLSession.shared.data(for: запрос),
                  ((пара.1 as? HTTPURLResponse)?.statusCode ?? 200) == 200,
                  let текст = String(data: пара.0, encoding: .utf8),
                  let каталог = разобрать(текст), !каталог.пустой else { continue }
            return каталог
        }
        return nil
    }

    /// Из текста cats-*.js — JSON между «MK_CATS=» и последней «]».
    private static func разобрать(_ текст: String) -> КаталогПоиска? {
        guard let метка = текст.range(of: "MK_CATS="),
              let конец = текст.range(of: "]", options: .backwards),
              метка.upperBound < конец.upperBound else { return nil }
        let json = String(текст[метка.upperBound..<конец.upperBound])
        guard let данные = json.data(using: .utf8),
              let дерево = (try? JSONSerialization.jsonObject(with: данные)) as? [[String: Any]] else { return nil }
        var каталог = КаталогПоиска()
        обойти(дерево, родитель: nil, в: &каталог)
        return каталог
    }

    private static func обойти(_ ветви: [[String: Any]], родитель: String?, в каталог: inout КаталогПоиска) {
        for ветвь in ветви {
            guard let ключ = ветвь["slug"] as? String, !ключ.isEmpty else { continue }
            let узел = КаталогПоиска.Узел(имя: (ветвь["name"] as? String) ?? "", родитель: родитель,
                                          краска: (ветвь["color"] as? String) ?? "",
                                          бренды: (ветвь["brands"] as? [String]) ?? [])
            каталог.добавить(ключ, узел)
            обойти((ветвь["children"] as? [[String: Any]]) ?? [], родитель: ключ, в: &каталог)
        }
    }
}
