import Foundation

/**
 Тексты цифровых товаров (ultra-site 16.10.2026, ListingDigital.swift) на языке приложения (kk/ru/en/ar), тем же способом,
 что КнопкиОбъявленияText. Строка «Эта возможность недоступна в приложении» — не здесь: это общий текст всех цифровых
 функций, БизнесText «no_digital». Ни ссылок, ни слов «купите на сайте»: правка и код — «в веб-версии кабинета», и только
 там, где задание сайта велит это сказать (Ц4, Ц5).
 */
enum ЦифровоеText {
    static func т(_ ключ: String) -> String {
        let язык = DesignText.язык          // запомненный за запуск, а не настройки телефона на каждую подпись
        return тексты[язык]?[ключ] ?? тексты["ru"]?[ключ] ?? ключ
    }

    /// Вид кода (digital_info.kind) словами; неизвестный — пусто.
    static func вид(_ код: String) -> String {
        let ключ = "kind_" + код.lowercased()
        let слово = т(ключ)
        return слово == ключ ? "" : слово
    }

    /// Регион активации (digital_info.region) словами; неизвестный — как пришёл (код региона).
    static func регион(_ код: String) -> String {
        let ключ = "reg_" + код.uppercased()
        let слово = т(ключ)
        return слово == ключ ? код : слово
    }

    private static let тексты: [String: [String: String]] = [
        "ru": [
            "badge": "Цифровой товар",
            "edit_web": "Правка цифровых товаров — в веб-версии кабинета",
            "deal_code_web": "Цифровой код открывается в веб-версии кабинета",
            "seller_stats": "Цифровых продаж: %d, споров: %d",
            "platform": "Платформа",
            "region": "Регион активации",
            "nominal": "Номинал",
            "valid_until": "Действует до %@",
            "code_expired": "Срок действия кода истёк",
            "expired_short": "Срок истёк",
            "kind_game_key": "Игровой ключ",
            "kind_gift_card": "Подарочная карта",
            "kind_license": "Лицензия",
            "kind_subscription": "Подписка",
            "kind_ticket": "Электронный билет",
            "reg_KZ": "Казахстан",
            "reg_CIS": "СНГ",
            "reg_GLOBAL": "Весь мир",
            "reg_EU": "Европа",
            "reg_US": "США",
        ],
        "kk": [
            "badge": "Цифрлық тауар",
            "edit_web": "Цифрлық тауарларды өңдеу — кабинеттің веб-нұсқасында",
            "deal_code_web": "Цифрлық код кабинеттің веб-нұсқасында ашылады",
            "seller_stats": "Цифрлық сатылым: %d, дау: %d",
            "platform": "Платформа",
            "region": "Белсендіру өңірі",
            "nominal": "Номинал",
            "valid_until": "%@ дейін жарамды",
            "code_expired": "Кодтың жарамдылық мерзімі өтті",
            "expired_short": "Мерзімі өтті",
            "kind_game_key": "Ойын кілті",
            "kind_gift_card": "Сыйлық картасы",
            "kind_license": "Лицензия",
            "kind_subscription": "Жазылым",
            "kind_ticket": "Электрондық билет",
            "reg_KZ": "Қазақстан",
            "reg_CIS": "ТМД",
            "reg_GLOBAL": "Бүкіл әлем",
            "reg_EU": "Еуропа",
            "reg_US": "АҚШ",
        ],
        "en": [
            "badge": "Digital item",
            "edit_web": "Digital items are edited in the web version of your account",
            "deal_code_web": "The digital code opens in the web version of your account",
            "seller_stats": "Digital sales: %d, disputes: %d",
            "platform": "Platform",
            "region": "Activation region",
            "nominal": "Face value",
            "valid_until": "Valid until %@",
            "code_expired": "This code has expired",
            "expired_short": "Expired",
            "kind_game_key": "Game key",
            "kind_gift_card": "Gift card",
            "kind_license": "License",
            "kind_subscription": "Subscription",
            "kind_ticket": "E-ticket",
            "reg_KZ": "Kazakhstan",
            "reg_CIS": "CIS",
            "reg_GLOBAL": "Worldwide",
            "reg_EU": "Europe",
            "reg_US": "USA",
        ],
        "ar": [
            "badge": "منتج رقمي",
            "edit_web": "يتم تعديل المنتجات الرقمية في نسخة الويب من الحساب",
            "deal_code_web": "يُفتح الرمز الرقمي في نسخة الويب من الحساب",
            "seller_stats": "مبيعات رقمية: %d، نزاعات: %d",
            "platform": "المنصة",
            "region": "منطقة التفعيل",
            "nominal": "القيمة الاسمية",
            "valid_until": "صالح حتى %@",
            "code_expired": "انتهت صلاحية الرمز",
            "expired_short": "منتهي الصلاحية",
            "kind_game_key": "مفتاح لعبة",
            "kind_gift_card": "بطاقة هدية",
            "kind_license": "ترخيص",
            "kind_subscription": "اشتراك",
            "kind_ticket": "تذكرة إلكترونية",
            "reg_KZ": "كازاخستان",
            "reg_CIS": "رابطة الدول المستقلة",
            "reg_GLOBAL": "جميع أنحاء العالم",
            "reg_EU": "أوروبا",
            "reg_US": "الولايات المتحدة",
        ],
    ]
}
