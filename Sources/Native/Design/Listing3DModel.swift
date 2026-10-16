import Foundation

/**
 3D-ОБЗОР ОБЪЯВЛЕНИЯ — ДАННЫЕ (владелец 14.10.2026: «3D-обзор надо сделать за счёт ИИ — 5 разных фото, и ИИ сам собрал
 3D любой вещи или авто»; раньше: «чтобы по-настоящему по камере показывал объект в примерке»).

 Продавец при подаче снимает вещь (или машину) с пяти сторон: спереди, 45° спереди-слева, сбоку, 45° сзади-слева,
 сзади. Каждый кадр вырезается движком студии (ВырезкаПредмета), сервер по ним собирает 3D-модель ИИ (image-to-3D).
 В ответе api/listings.php (элемент ленты и ?id=) у объявления — необязательное поле:

   "model3d": {"usdz": "https://…/m.usdz", "glb": "https://…/m.glb", "poster": "https://…/p.jpg",
               "w_cm": 60, "h_cm": 85, "d_cm": 55, "ai": true, "angles": ["https://…/a1.png", …]}  или null.

 "angles" может прийти и без usdz (модель ещё собирается или не вышла) — тогда покупатель видит «Обзор 360°»: ракурсы
 листаются пальцем как поворот. Есть usdz — «3D»: модель вращается и приближается, «В комнате» ставит её через AR
 Quick Look (Listing3DViewer.swift). Ни того, ни другого — поля как будто нет.

 🔴 РАЗБОР ТЕРПИМЫЙ, как у всего Listing: числа — числом или строкой, ai — true/1/"1". Адреса — только https на kliko.kz
 или его поддомене (путь от корня — от https://kliko.kz); чужой хост, http и прочее — адреса нет. Сломанное поле не
 роняет объявление: Listing берёт его через try? — не разобралось, значит nil.

 Тип общий для трёх направлений: «просмотр» (этот файл и Listing3D*.swift), «подача» (съёмка ракурсов) и «Поместится
 ли?» (режим «Вещь»). Локальный USDZ из кэша или скачанный — МодельОбъёмаОбъявления.файлМодели(_:), кэш на диске с
 пределом — КэшОбъёма (Listing3DCache.swift). Поэлементный init принимает и адреса файлов на телефоне (file://) — так
 подача может показать ещё не отправленные ракурсы тем же экраном.
 */
extension Config {
    /// 3D-обзор на странице объявления: значок «3D» / «360°» на фото, кнопка «Смотреть в 3D» / «Обзор 360°» и экран
    /// просмотра. Без поля model3d в ответе сервера ничего не видно; false — не видно и с ним.
    static let объёмОбъявления = true
}

struct МодельОбъёмаОбъявления: Sendable, Hashable, Decodable {
    /// USDZ — для RealityKit и AR Quick Look. nil — модели нет (ещё собирается или не вышла).
    let usdz: URL?
    /// GLB — для сайта и Android; приложение его не качает, держим для полноты.
    let glb: URL?
    /// Картинка-обложка модели — под колесом загрузки, пока качается USDZ.
    let постер: URL?
    /// Реальные размеры, см: ширина, высота, глубина. Все три — модель в USDZ в настоящем размере (AR без масштаба).
    let ширинаСм: Double?
    let высотаСм: Double?
    let глубинаСм: Double?
    /// Модель собрал ИИ по фото (ai). Не пришло — да: так честнее, подпись «создана ИИ» лишней не бывает.
    let созданаИИ: Bool
    /// Ракурсы-вырезки PNG в порядке съёмки: спереди → 45° спереди-слева → сбоку → 45° сзади-слева → сзади.
    let ракурсы: [URL]

    init(usdz: URL?, glb: URL? = nil, постер: URL? = nil, ширинаСм: Double? = nil, высотаСм: Double? = nil,
         глубинаСм: Double? = nil, созданаИИ: Bool = true, ракурсы: [URL] = []) {
        self.usdz = usdz
        self.glb = glb
        self.постер = постер
        self.ширинаСм = Self.размер(ширинаСм)
        self.высотаСм = Self.размер(высотаСм)
        self.глубинаСм = Self.размер(глубинаСм)
        self.созданаИИ = созданаИИ
        self.ракурсы = ракурсы
    }

    // MARK: Что показывать

    /// Есть 3D-модель — значок «3D», экран с вращением и «В комнате».
    var есть3D: Bool { usdz != nil }
    /// Есть хотя бы два ракурса — можно «Обзор 360°».
    var есть360: Bool { ракурсы.count >= 2 }
    /// Показывать ли вообще что-то.
    var естьЧтоПоказать: Bool { есть3D || есть360 }
    /// Все три размера известны — модель в настоящем размере: AR Quick Look без масштабирования, «Вещь» — как есть.
    var размерыИзвестны: Bool { габаритыСм != nil }

    /// Ширина, высота, глубина, см — только все три сразу.
    var габаритыСм: (ширина: Double, высота: Double, глубина: Double)? {
        guard let ш = ширинаСм, let в = высотаСм, let г = глубинаСм else { return nil }
        return (ш, в, г)
    }

    // MARK: Разбор

    private struct Ключ: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ s: String) { stringValue = s }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    /// Не пришло ни модели, ни двух ракурсов — бросает: Listing через try? получает nil, как будто поля нет.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Ключ.self)

        func строка(_ k: String) -> String? {
            guard let s = try? c.decode(String.self, forKey: Ключ(k)) else { return nil }
            let чистая = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return чистая.isEmpty ? nil : чистая
        }
        func число(_ k: String) -> Double? {
            if let d = try? c.decode(Double.self, forKey: Ключ(k)) { return d }
            if let s = try? c.decode(String.self, forKey: Ключ(k)) {
                return Double(s.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: "."))
            }
            return nil
        }
        func да(_ k: String) -> Bool? {
            if let b = try? c.decode(Bool.self, forKey: Ключ(k)) { return b }
            if let i = try? c.decode(Int.self, forKey: Ключ(k)) { return i != 0 }
            if let s = try? c.decode(String.self, forKey: Ключ(k)) {
                let м = s.lowercased()
                if м == "1" || м == "true" { return true }
                if м == "0" || м == "false" { return false }
            }
            return nil
        }

        usdz = строка("usdz").flatMap(Self.адрес)
        glb = строка("glb").flatMap(Self.адрес)
        постер = строка("poster").flatMap(Self.адрес)
        ширинаСм = Self.размер(число("w_cm"))
        высотаСм = Self.размер(число("h_cm"))
        глубинаСм = Self.размер(число("d_cm"))
        созданаИИ = да("ai") ?? true
        /* Ракурсы: массив строк — по одному элементу: не строка (null, число, объект) — мимо, а не весь список; PHP
           отдал массив объектом ({"0": …, "2": …} после unset) — значения по порядку ключей. Чужие адреса и повторы —
           мимо. Больше пределРакурсов не берём: экран «360°» держит все кадры в памяти. */
        var список: [URL] = []
        for запись in Self.строкиРакурсов(c, Ключ("angles")) {
            guard let адрес = Self.адрес(запись), !список.contains(адрес) else { continue }
            список.append(адрес)
            if список.count >= Self.пределРакурсов { break }
        }
        ракурсы = список

        guard usdz != nil || список.count >= 2 else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath,
                                                    debugDescription: "model3d: ни usdz, ни двух ракурсов"))
        }
    }

    /// Больше ракурсов не берём: по договору их 5, а «360°» держит в памяти каждый кадр.
    static let пределРакурсов = 12

    /// Элемент массива, который не строка: декодер шагает через него, ничего не читая.
    private struct ПропускРакурса: Decodable {
        init(from decoder: Decoder) throws {}
    }

    /// Строки ракурсов: массив (по элементу, непонятные — мимо) или объект с ключами-номерами (по порядку номеров).
    private static func строкиРакурсов(_ c: KeyedDecodingContainer<Ключ>, _ ключ: Ключ) -> [String] {
        var итог: [String] = []
        if var массив = try? c.nestedUnkeyedContainer(forKey: ключ) {
            while !массив.isAtEnd {
                if (try? массив.decodeNil()) == true { continue }
                if let строка = try? массив.decode(String.self) {
                    итог.append(строка)
                } else if (try? массив.decode(ПропускРакурса.self)) == nil {
                    break
                }
            }
            return итог
        }
        guard let объект = try? c.nestedContainer(keyedBy: Ключ.self, forKey: ключ) else { return [] }
        let ключи = объект.allKeys.sorted { а, б in
            let на = Int(а.stringValue) ?? Int.max
            let нб = Int(б.stringValue) ?? Int.max
            return на != нб ? на < нб : а.stringValue < б.stringValue
        }
        for к in ключи {
            if let строка = try? объект.decode(String.self, forKey: к) { итог.append(строка) }
        }
        return итог
    }

    /// Адрес файла модели или ракурса: https на kliko.kz или поддомене; путь от корня — от https://kliko.kz. Иначе nil.
    static func адрес(_ строка: String) -> URL? {
        let чистая = строка.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !чистая.isEmpty else { return nil }
        let адрес: URL?
        if чистая.hasPrefix("/") && !чистая.hasPrefix("//") {
            адрес = URL(string: чистая, relativeTo: Config.apiBase)?.absoluteURL
        } else {
            адрес = URL(string: чистая)
        }
        guard let адрес, адрес.scheme?.lowercased() == "https", let хост = адрес.host?.lowercased() else { return nil }
        guard хост == "kliko.kz" || хост.hasSuffix(".kliko.kz") else { return nil }
        return адрес
    }

    /// Размер, см: от 0,5 до 5000 (машина, контейнер); прочее — нет размера.
    private static func размер(_ см: Double?) -> Double? {
        guard let см, см.isFinite, см >= 0.5, см <= 5000 else { return nil }
        return см
    }

    // MARK: Для «Поместится ли?» и других

    /**
     Локальный USDZ модели: из кэша на диске (Caches, предел 200 МБ — КэшОбъёма) или скачанный сейчас. Нет usdz, нет
     сети, файл не USDZ, больше `предел` байт (свой предел вызывающего, nil — общий 150 МБ), задачу отменили — nil.
     Адрес file:// (подача, ещё не отправлено) — он же, без скачивания. Имя на диске — всегда «.usdz», как бы ни
     кончался путь адреса. Зовёт режим «Вещь» «Поместится ли?»: модель в реальном размере, если размерыИзвестны.
     */
    static func файлМодели(_ м: МодельОбъёмаОбъявления, предел: Int64? = nil) async -> URL? {
        guard let адрес = м.usdz else { return nil }
        return try? await КэшОбъёма.shared.файл(адрес, прогресс: nil, расширение: "usdz", предел: предел)
    }

    /// «60 × 85 × 55 см» — цифрами языка телефона; размеров нет — nil.
    var текстГабаритов: String? {
        guard let г = габаритыСм else { return nil }
        let ч = [г.ширина, г.высота, г.глубина].map(Self.см)
        return ч.joined(separator: " × ") + " " + ОбъёмText.т("o3_cm")
    }

    /// Сантиметры без лишних нулей: 60, 85.5.
    static func см(_ значение: Double) -> String {
        форматСм.string(from: NSNumber(value: значение)) ?? String(Int(значение.rounded()))
    }

    /// Скорость: форматтер — один на запуск (после создания не меняется — его можно звать с любой нити).
    private static let форматСм: NumberFormatter = {
        let формат = NumberFormatter()
        формат.locale = .autoupdatingCurrent
        формат.numberStyle = .decimal
        формат.maximumFractionDigits = 1
        формат.minimumFractionDigits = 0
        формат.usesGroupingSeparator = false
        return формат
    }()
}

extension Listing {
    /// Есть ли у объявления что показать в 3D-обзоре (и включён ли рубильник).
    var естьОбъём: Bool {
        guard Config.объёмОбъявления, let м = модельОбъёма else { return false }
        return м.естьЧтоПоказать
    }
}
