import Foundation

/**
 «ПОКАЗАТЬ НА ПРИМЕРЕ» — ДЕМОНСТРАЦИЯ ИМПОРТА (aiDemoFill сайта, js/cabinet-deals.min.js).

 Кнопка #ai-imp-demo-btn на карточке «Прайс, таблица или фото». Сайт вставляет в поле пример прайса, показывает ход
 разбора (шаг 220 мс, +7…24 %), подписи «анализирую ваш прайс» и «распознано N из 6», «Готово — распознано товаров» и
 через 550 мс — шесть готовых строк со значком «Kliko AI · осталось 42». Ни одного запроса: квота Kliko AI не
 тратится, «Добавить в «Неактивные»» черновиков не создаёт — только плашка «Это демонстрация…» (aiPublish при
 _aiDemoMode).

 Русский пример — слово в слово с сайта; казахский, английский и арабский — тот же набор товаров на языке телефона.
 */
enum ПримерИмпорта {
    /// Текст прайса, который сайт кладёт в поле #ai-imp-text.
    static func текст(_ язык: String) -> String {
        let строки: [String]
        switch язык {
        case "kk":
            строки = [
                "Айфон 13 128гб көк, жағдайы өте жақсы — 250000",
                "ноут асус ROG Strix G15 rtx3060 жаңа 520 000тг",
                "кроссовка nike air max 90 жаңа 35000",
                "кофемашина delonghi magnifica s 180к қолданылған",
                "робот-шаңсорғыш xiaomi vacuum s10 95000 жаңа",
                "велосипед trek marlin 5 210000 қолданылған"
            ]
        case "en":
            строки = [
                "iphone 13 128gb blue great cond — 250000",
                "asus ROG Strix G15 laptop rtx3060 new 520 000tg",
                "nike air max 90 sneakers new 35000",
                "delonghi magnifica s coffee machine 180k used",
                "xiaomi vacuum s10 robot vacuum 95000 new",
                "trek marlin 5 bike 210000 used"
            ]
        case "ar":
            строки = [
                "آيفون 13 128 جيجا أزرق حالة ممتازة — 250000",
                "لابتوب asus ROG Strix G15 rtx3060 جديد 520 000 تنغي",
                "حذاء nike air max 90 جديد 35000",
                "ماكينة قهوة delonghi magnifica s 180 ألف مستعملة",
                "مكنسة روبوت xiaomi vacuum s10 95000 جديدة",
                "دراجة trek marlin 5 210000 مستعملة"
            ]
        default:
            строки = [
                "Айфон 13 128гб синий отл сост — 250000",
                "ноут асус ROG Strix G15 rtx3060 новый 520 000тг",
                "кроссы nike air max 90 новые 35000",
                "кофемашина delonghi magnifica s 180к бу",
                "робот-пылесос xiaomi vacuum s10 95000 новый",
                "велосипед trek marlin 5 210000 бу"
            ]
        }
        return строки.joined(separator: "\n")
    }

    /// Готовые строки примера (массив e в aiDemoFill): название, бренд, цена, состояние, раздел, у ноутбука —
    /// процессор, память и накопитель.
    static func строки(_ язык: String) -> [[String: Any]] {
        let названия: [String]
        let разделы: [String]
        let гб: String
        switch язык {
        case "kk":
            названия = ["iPhone 13 128GB, жағдайы өте жақсы", "ASUS ROG Strix G15 ноутбугі, RTX 3060",
                        "Nike Air Max 90 кроссовкалары", "DeLonghi Magnifica S кофемашинасы",
                        "Xiaomi Vacuum S10 робот-шаңсорғышы", "Trek Marlin 5 велосипеді"]
            разделы = ["Смартфондар", "Ноутбуктер", "Аяқ киім", "Ас үй техникасы", "Үй техникасы", "Велосипедтер"]
            гб = "ГБ"
        case "en":
            названия = ["iPhone 13 128GB, excellent condition", "ASUS ROG Strix G15 laptop, RTX 3060",
                        "Nike Air Max 90 sneakers", "DeLonghi Magnifica S coffee machine",
                        "Xiaomi Vacuum S10 robot vacuum", "Trek Marlin 5 bicycle"]
            разделы = ["Smartphones", "Laptops", "Shoes", "Kitchen appliances", "Home appliances", "Bicycles"]
            гб = "GB"
        case "ar":
            названия = ["iPhone 13 سعة 128 جيجابايت، حالة ممتازة", "لابتوب ASUS ROG Strix G15، RTX 3060",
                        "حذاء Nike Air Max 90 الرياضي", "ماكينة قهوة DeLonghi Magnifica S",
                        "مكنسة روبوت Xiaomi Vacuum S10", "دراجة Trek Marlin 5"]
            разделы = ["الهواتف الذكية", "أجهزة اللابتوب", "الأحذية", "أجهزة المطبخ", "الأجهزة المنزلية", "الدراجات"]
            гб = "جيجابايت"
        default:
            названия = ["iPhone 13 128GB, отличное состояние", "Ноутбук ASUS ROG Strix G15, RTX 3060",
                        "Кроссовки Nike Air Max 90", "Кофемашина DeLonghi Magnifica S",
                        "Робот-пылесос Xiaomi Vacuum S10", "Велосипед Trek Marlin 5"]
            разделы = ["Смартфоны", "Ноутбуки", "Обувь", "Техника для кухни", "Техника для дома", "Велосипеды"]
            гб = "ГБ"
        }
        let бренды = ["Apple", "ASUS", "Nike", "DeLonghi", "Xiaomi", "Trek"]
        let цены = [250_000, 520_000, 35_000, 180_000, 95_000, 210_000]
        let состояния = ["used", "new", "new", "used", "new", "used"]
        var итог: [[String: Any]] = []
        for i in 0..<названия.count {
            var строка: [String: Any] = [:]
            строка["title"] = названия[i]
            строка["brand"] = бренды[i]
            строка["price"] = цены[i]
            строка["condition"] = состояния[i]
            строка["category"] = разделы[i]
            if i == 1 {
                строка["cpu"] = "Ryzen 7"
                строка["ram"] = "16 " + гб
                строка["storage"] = "512 " + гб
            }
            итог.append(строка)
        }
        return итог
    }

    /// «Kliko AI · осталось 42» — _lastAiMeta примера.
    static let осталосьИИ = 42
}
