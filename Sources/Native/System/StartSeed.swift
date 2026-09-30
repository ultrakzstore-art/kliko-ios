import Foundation

/**
 СТАРТОВЫЕ ДАННЫЕ В СБОРКЕ (скорость первого запуска после установки).

 Без них первый запуск ждал сеть, чтобы показать полосу разделов, лист «Категории», названия разделов, мастер подачи
 (разделы, характеристики, регионы), марки авто и типы запчастей. Теперь всё это лежит в приложении — Seed/seed-*.json
 (подключены ресурсом в project.yml, обновляет scripts/fetch_seed.sh) — и показывается сразу; свежие данные сайта
 приходят следом и подменяют стартовые. Объявлений здесь нет: они устаревают за часы, до ответа сети — серые карточки.

 Файлы маленькие (до 300 КБ вместе) и читаются только когда нужны, один раз.
 */
enum СтартовыеДанные {
    /// Сырой файл из сборки: seed-cats, seed-cab-refs, seed-auto, seed-parts.
    static func данные(_ имя: String) -> Data? {
        guard let адрес = Bundle.main.url(forResource: имя, withExtension: "json") else { return nil }
        return try? Data(contentsOf: адрес, options: .mappedIfSafe)
    }

    /// Файл из сборки как объект JSON.
    static func объект(_ имя: String) -> [String: Any]? {
        guard let д = данные(имя) else { return nil }
        return (try? JSONSerialization.jsonObject(with: д)) as? [String: Any]
    }

    /**
     Дерево разделов в виде MK_CATS сайта ([{slug, name, color, brands, children}]) на языке сайта: ru, kz, en, ar.
     В файле узлы записаны один раз (ключ, номер родителя, цвет — пусто, если как у родителя, бренды), имена — по языкам;
     нет имени на этом языке — русское.
     */
    static func дерево(_ язык: String) -> [[String: Any]] {
        guard let всё = объект("seed-cats"), let узлы = всё["nodes"] as? [[Any]],
              let имена = всё["names"] as? [String: [String]] else { return [] }
        let свои = имена[язык] ?? []
        let русские = имена["ru"] ?? []
        var дети = [[Int]](repeating: [], count: узлы.count)
        var корни: [Int] = []
        var краски = [String](repeating: "", count: узлы.count)
        for (номер, узел) in узлы.enumerated() {
            let родитель = узел.count > 1 ? ((узел[1] as? Int) ?? -1) : -1
            let своя = узел.count > 2 ? ((узел[2] as? String) ?? "") : ""
            let естьРодитель = родитель >= 0 && родитель < номер
            краски[номер] = своя.isEmpty && естьРодитель ? краски[родитель] : своя
            if естьРодитель {
                дети[родитель].append(номер)
            } else {
                корни.append(номер)
            }
        }
        func имя(_ н: Int) -> String {
            if н < свои.count, !свои[н].isEmpty { return свои[н] }
            return н < русские.count ? русские[н] : ""
        }
        func ветвь(_ н: Int) -> [String: Any] {
            let узел = узлы[н]
            var в: [String: Any] = [:]
            в["slug"] = (узел.first as? String) ?? ""
            в["name"] = имя(н)
            в["color"] = краски[н]
            if узел.count > 3, let бренды = узел[3] as? [String] { в["brands"] = бренды }
            let потомки = дети[н]
            if !потомки.isEmpty { в["children"] = потомки.map { ветвь($0) } }
            return в
        }
        return корни.map { ветвь($0) }
    }

    /// Дерево разделов текстом «var MK_CATS=[…]» — тем же, что разбирает СправочникиПодачи.
    static func файлРазделов(_ язык: String) -> [UInt8]? {
        let ветви = дерево(язык)
        guard !ветви.isEmpty, let json = try? JSONSerialization.data(withJSONObject: ветви) else { return nil }
        return Array("var MK_CATS=".utf8) + Array(json)
    }

    /// Справочники кабинета текстом «var KLK_CAB_REFS={…}» (E_SPECS, BRAND_LIST, REALTY_FIELDS, PARTS_FIELDS, GEO_KZ).
    static func файлСправочников() -> [UInt8]? {
        guard let json = данные("seed-cab-refs"), !json.isEmpty else { return nil }
        return Array("var KLK_CAB_REFS=".utf8) + Array(json)
    }

    /// Язык сайта из адреса файла разделов (/js/cats-kz.js?v=… → kz); не разобрали — ru.
    static func языкРазделов(_ путь: String) -> String {
        guard let начало = путь.range(of: "cats-") else { return "ru" }
        let хвост = путь[начало.upperBound...]
        let язык = хвост.prefix { $0.isLetter }
        return язык.isEmpty ? "ru" : String(язык)
    }

    /// Модели марки из сборки: [имя, [кузов]] — без поколений (их даёт только сеть).
    static func моделиМарки(_ марка: String) -> [(имя: String, кузов: [String])] {
        guard let всё = объект("seed-auto"), let модели = всё["models"] as? [String: Any] else { return [] }
        let нужная = марка.lowercased()
        guard let пара = модели.first(where: { $0.key.lowercased() == нужная }),
              let список = пара.value as? [[Any]] else { return [] }
        return список.compactMap { запись -> (имя: String, кузов: [String])? in
            guard let имя = запись.first as? String, !имя.isEmpty else { return nil }
            let кузов = запись.count > 1 ? ((запись[1] as? [String]) ?? []) : []
            return (имя: имя, кузов: кузов)
        }
    }
}
