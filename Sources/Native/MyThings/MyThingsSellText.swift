import Foundation

/**
 Тексты «Продать своё» из «Моего» (пачка 83, MyThingsSell.swift; дом, устройства и компьютер целиком — владелец
 17.10.2026, MyThingsSellHome.swift): названия заготовки подачи и кнопки «Продать». Ключи
 msl_*; языки ru, kk, en, ar, прочие — русский (язык — тот же, что у примерочной: ПримерочнаяText.язык). Строки с %@
 идут через String(format:). В названиях — только вид и значения вещи, без своих названий «Моего» (§16.4).
 */
enum ПродатьМоёText {
    static func т(_ ключ: String) -> String {
        словарь[ключ] ?? ru[ключ] ?? ключ
    }

    static func ф(_ ключ: String, _ аргумент: String) -> String {
        String(format: т(ключ), аргумент)
    }

    private static var словарь: [String: String] {
        switch ПримерочнаяText.язык {
        case "kk": return kk
        case "en": return en
        case "ar": return ar
        default: return ru
        }
    }

    private static let ru: [String: String] = [
        "msl_tyres": "Шины %@, комплект",
        "msl_rims": "Диски %@, комплект",
        "msl_ram": "Оперативная память %@",
        "msl_ssd": "SSD %@",
        "msl_hdd": "Жёсткий диск %@",
        "msl_gpu": "Видеокарта %@",
        "msl_psu": "Блок питания %@",
        "msl_cpu": "Процессор %@",
        "msl_laptop_plain": "Ноутбук",
        "msl_desktop_plain": "Компьютер",
        "msl_mattress": "Матрас %@",
        "msl_sell": "Продать",
        "msl_sell_tyres": "Шины %@",
        "msl_sell_rims": "Диски %@",
        "msl_sell_hint": "Откроем подачу уже заполненной — останется проверить и указать цену"
    ]

    private static let kk: [String: String] = [
        "msl_tyres": "Шиналар %@, жиынтық",
        "msl_rims": "Дискілер %@, жиынтық",
        "msl_ram": "Жедел жады %@",
        "msl_ssd": "SSD %@",
        "msl_hdd": "Қатқыл диск %@",
        "msl_gpu": "Бейнекарта %@",
        "msl_psu": "Қуат блогы %@",
        "msl_cpu": "Процессор %@",
        "msl_laptop_plain": "Ноутбук",
        "msl_desktop_plain": "Компьютер",
        "msl_mattress": "Матрас %@",
        "msl_sell": "Сату",
        "msl_sell_tyres": "Шиналар %@",
        "msl_sell_rims": "Дискілер %@",
        "msl_sell_hint": "Хабарландыру толтырылған күйде ашылады — тексеріп, бағасын көрсету ғана қалады"
    ]

    private static let en: [String: String] = [
        "msl_tyres": "Tires %@, set",
        "msl_rims": "Wheels %@, set",
        "msl_ram": "RAM %@",
        "msl_ssd": "SSD %@",
        "msl_hdd": "Hard drive %@",
        "msl_gpu": "Graphics card %@",
        "msl_psu": "Power supply %@",
        "msl_cpu": "Processor %@",
        "msl_laptop_plain": "Laptop",
        "msl_desktop_plain": "Desktop PC",
        "msl_mattress": "Mattress %@",
        "msl_sell": "Sell",
        "msl_sell_tyres": "Tires %@",
        "msl_sell_rims": "Wheels %@",
        "msl_sell_hint": "The listing opens already filled in — just check it and add the price"
    ]

    private static let ar: [String: String] = [
        "msl_tyres": "إطارات %@، طقم",
        "msl_rims": "جنوط %@، طقم",
        "msl_ram": "ذاكرة وصول عشوائي %@",
        "msl_ssd": "SSD %@",
        "msl_hdd": "قرص صلب %@",
        "msl_gpu": "بطاقة رسوميات %@",
        "msl_psu": "مزوّد طاقة %@",
        "msl_cpu": "معالج %@",
        "msl_laptop_plain": "حاسوب محمول",
        "msl_desktop_plain": "حاسوب مكتبي",
        "msl_mattress": "مرتبة %@",
        "msl_sell": "بيع",
        "msl_sell_tyres": "إطارات %@",
        "msl_sell_rims": "جنوط %@",
        "msl_sell_hint": "سيفتح الإعلان معبّأً مسبقًا — يبقى أن تراجعه وتضيف السعر"
    ]
}
