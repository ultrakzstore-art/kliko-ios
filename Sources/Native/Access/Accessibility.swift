import Foundation

/**
 ДОСТУПНОСТЬ — ЭТАП 11 ПЕРЕХОДА НА SWIFTUI (владелец 25.09.2026: «5–7 этапов наперёд»).

 VoiceOver читает карточку объявления одной фразой — «название, цена, город», а за ними «в топе» и «новое», если на
 карточке есть эти метки. Фото — украшение: без своей подписи VoiceOver читал бы у заглушки имя значка («photo»).
 Сообщение в переписке — «Вы: …» или «<собеседник>: …» и время, одной фразой, а не текст и время по отдельности.

 Цена для голоса своя: без разделителей разрядов и словом «тенге». «14 900 000 ₸» синтезатор читает кусками по три
 цифры, а ₸ — как «знак тенге». Рубильника у подписей нет: выключать их незачем, на экране они ничего не меняют.
 */
extension Listing {
    /// «iPhone 15, 450000 тенге, Алматы, в топе».
    var голос: String {
        var части = [title, ценаГолосом, city]
        if isTop { части.append(AccessText.т("top")) }
        if isNew { части.append(AccessText.т("new")) }
        return части.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// Цена так, как её надо сказать: «5000 тенге в сутки», «Договорная».
    var ценаГолосом: String {
        if forRent, let день = rentPriceDay, день > 0 {
            return ГолосЦены.тенге(день) + " " + AccessText.т("per_day")
        }
        guard let сумма = price, сумма > 0 else {
            return FeedText.т(negotiable ? "neg" : "noprice")
        }
        return ГолосЦены.тенге(сумма)
    }
}

/// Сумма для голоса: цифры подряд и слово «тенге».
enum ГолосЦены {
    static func тенге(_ сумма: Double) -> String {
        (формат.string(from: NSNumber(value: сумма)) ?? "") + " " + AccessText.т("tenge")
    }

    private static let формат: NumberFormatter = {
        let ф = NumberFormatter()
        ф.numberStyle = .decimal
        ф.usesGroupingSeparator = false
        ф.maximumFractionDigits = 0
        return ф
    }()
}

extension ЧатСообщение {
    /// «Вы: здравствуйте, 14:05» или «Айдар: фото, 14:06». Фото и голосовое — словом, без значков 📷 и 🎤.
    func голос(собеседник: String) -> String {
        let что: String
        switch тип {
        case "image": что = ChatText.т("photo")
        case "voice": что = ChatText.т("voice")
        default:      что = текст
        }
        let время = ЧатВремя.время(когда)
        /* Владелец 25.09.2026, проверка на телефоне, сборка 33: уведомление («Продавец вышел из чата») — без автора:
           «Вы: Покупатель отозвал…» VoiceOver прочёл бы так же неверно, как это было написано в списке. */
        if системное { return что + (время.isEmpty ? "" : ", " + время) }
        let кто = моё ? ChatText.т("you") : ((собеседник.isEmpty ? ChatText.т("peer") : собеседник) + ": ")
        return кто + что + (время.isEmpty ? "" : ", " + время)
    }
}
