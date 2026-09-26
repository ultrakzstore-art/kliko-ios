import Foundation
import UIKit
import CoreImage

/**
 ДОКУМЕНТЫ B2B СВОИМИ СРЕДСТВАМИ: СЧЁТ, АКТ Р-1, НАКЛАДНАЯ З-2, ДОГОВОР ПОСТАВКИ, ДОВЕРЕННОСТЬ М-2а
 (владелец: «кабинет полностью SwiftUI»).

 У сайта эти документы собирает модуль business в браузере (_cmpPrintInvoice, _cmpPrintAct, _cmpPrintWaybill,
 _cmpPrintContract, _cmpPrintPOA; данные — _b2bDocData заказа B2B и invPrint полученного счёта) и печатает окном браузера.
 Здесь — та же разметка теми же словами (документ по-русски, как у сайта), только раскладка таблицами, а не flex/grid:
 её надёжно вёрстает UIMarkupTextPrintFormatter. Готовую разметку показывает ОкноДокумента (PDF, «Поделиться», «Печать»).
 Подпись и печать компании (sign/stamp из «Печать и подпись») сайт накладывает картинками после подтверждения eGov
 (seal_use) — здесь документ без факсимиле, с линиями для подписи, как печатный бланк сайта без «Подписать».
 */
struct ПозицияДокумента: Equatable {
    let название: String
    let количество: String
    let цена: Double
    let сумма: Double
}

struct ДанныеДокумента: Equatable {
    var вид = "invoice"
    var номер = ""
    var дата = ""
    var оплатитьДо = ""
    var компания: [String: String] = [:]
    var покупатель: [String: String] = [:]
    var позиции: [ПозицияДокумента] = []
    var подытог: Double = 0
    var ндс: Double = 0
    var ндсЕсть = false
    var ставка: Double = 0
    var режим = ""
    var итого: Double = 0
    var прописью = ""
    var лицо = ""
    var удостоверение = ""
    /// Прайс-лист, присланный контрагентом (type pricelist): готовая разметка сайта.
    var разметка = ""

    private typealias A = МоиОбъявленияAPI

    /// Словарь сторон — строки (name, bin, director, addr, bank, bik, iik, kbe, city, accountant).
    private static func стороны(_ сырое: Any?) -> [String: String] {
        var итог: [String: String] = [:]
        for (ключ, значение) in (сырое as? [String: Any]) ?? [:] {
            let т = МоиОбъявленияAPI.строка(значение)
            if !т.isEmpty { итог[ключ] = т }
        }
        return итог
    }

    /// «ДД.ММ.ГГГГ» из ISO или «ГГГГ-ММ-ДД ЧЧ:ММ:СС» сервера; пусто — сегодня.
    private static func датаДокумента(_ строка: String) -> String {
        let d = СделкиФормат.дата(строка) ?? Date()
        let ф = DateFormatter()
        ф.locale = Locale(identifier: "ru_RU")
        ф.dateFormat = "dd.MM.yyyy"
        return ф.string(from: d)
    }

    /// _b2bDocData: заказ B2B → данные документа. часть — "goods" (накладная) | "services" (акт) | nil (счёт целиком).
    init(заказ j: [String: Any], часть: String?) {
        let сырые: [[String: Any]] = ((j["items"] as? [Any]) ?? []).compactMap { $0 as? [String: Any] }
        var выбранные = сырые
        if let часть {
            let отобраны = сырые.filter { п in
                let вид = A.строка(п["kind"]).isEmpty ? "goods" : A.строка(п["kind"])
                return часть == "services" ? вид == "service" : вид != "service"
            }
            if !отобраны.isEmpty { выбранные = отобраны }
        }
        let всего = A.число(j["total"])
        let суммаЧасти = выбранные.reduce(0.0) { $0 + A.число($1["sum"]) }
        let доля = всего > 0 && выбранные.count != сырые.count ? суммаЧасти / всего : 1
        let оплачено = A.строка(j["paid_at"])
        номер = A.строка(j["no"])
        дата = Self.датаДокумента(часть == nil ? A.строка(j["created_at"]) : (оплачено.isEmpty ? A.строка(j["created_at"]) : оплачено))
        let до = A.строка(j["valid_until"])
        оплатитьДо = до.isEmpty ? "" : Self.датаДокумента(до)
        компания = Self.стороны(j["seller"])
        покупатель = Self.стороны(j["buyer"])
        позиции = выбранные.map { п in
            let скидка = A.целое(п["discount_pct"])
            let имя = A.строка(п["name"]) + (скидка > 0 ? " (−\(скидка)%)" : "")
            return ПозицияДокумента(название: имя, количество: A.строка(п["qty"]), цена: A.число(п["price"]),
                                    сумма: A.число(п["sum"]))
        }
        let подытогЗаказа = A.число(j["subtotal"])
        подытог = (доля == 1 && подытогЗаказа > 0) ? подытогЗаказа : суммаЧасти
        ндс = (A.число(j["vat"]) * доля).rounded()
        let режимНДС = A.строка(j["vat_mode"])
        ндсЕсть = режимНДС == "add" || режимНДС == "incl"
        режим = режимНДС
        ставка = A.число(j["vat_rate"])
        итого = (доля == 1 && всего > 0 ? всего : суммаЧасти).rounded()
        прописью = ДокументыБизнеса.прописью(Int(итого))
        вид = часть == "services" ? "act" : (часть == "goods" ? "waybill" : "invoice")
    }

    /// invPrint: полученный документ (invoice_list, роль buyer).
    init(полученный j: [String: Any]) {
        вид = A.строка(j["type"]).isEmpty ? "invoice" : A.строка(j["type"])
        номер = A.строка(j["no"])
        дата = A.строка(j["date"])
        компания = Self.стороны(j["company"])
        var п = Self.стороны(j["buyer"])
        if п["name"] == nil { п["name"] = A.строка(j["buyer_name"]) }
        if п["bin"] == nil { п["bin"] = A.строка(j["buyer_bin"]) }
        покупатель = п
        позиции = ((j["items"] as? [Any]) ?? []).compactMap { $0 as? [String: Any] }.map { п in
            ПозицияДокумента(название: A.строка(п["name"]), количество: A.строка(п["qty"]), цена: A.число(п["price"]),
                             сумма: п["sum"] == nil ? A.число(п["qty"]) * A.число(п["price"]) : A.число(п["sum"]))
        }
        подытог = A.число(j["subtotal"])
        ндс = A.число(j["vat"])
        ндсЕсть = A.да(j["vat_on"])
        ставка = A.число(j["rate"])
        режим = A.строка(j["mode"])
        итого = A.число(j["total"])
        let слова = A.строка(j["total_words"])
        прописью = слова.isEmpty ? ДокументыБизнеса.прописью(Int(итого.rounded())) : слова
        лицо = A.строка(j["poa_person"])
        удостоверение = A.строка(j["poa_doc"])
        разметка = A.строка(j["html"])
    }
}

enum ДокументыБизнеса {
    /// Заголовок документа («Счёт № 12»).
    static func заголовок(_ д: ДанныеДокумента) -> String {
        switch д.вид {
        case "act": return "Акт № " + д.номер
        case "waybill": return "Накладная № " + д.номер
        case "contract": return "Договор поставки № " + д.номер
        case "poa": return "Доверенность № " + д.номер
        case "pricelist": return "Прайс-лист"
        default: return "Счёт № " + д.номер
        }
    }

    /// Разметка документа по виду.
    static func разметка(_ д: ДанныеДокумента) -> String {
        switch д.вид {
        case "pricelist" where !д.разметка.isEmpty: return д.разметка
        case "act": return страница(заголовок(д), акт(д))
        case "waybill": return страница(заголовок(д), накладная(д))
        case "contract": return страница(заголовок(д), договор(д))
        case "poa": return страница(заголовок(д), доверенность(д))
        default: return страница(заголовок(д), счёт(д))
        }
    }

    // MARK: - Общее

    static func экран(_ текст: String) -> String {
        var s = текст.replacingOccurrences(of: "&", with: "&amp;")
        s = s.replacingOccurrences(of: "<", with: "&lt;")
        s = s.replacingOccurrences(of: ">", with: "&gt;")
        return s.replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// _cmpMoney: «12 345».
    static func деньги(_ n: Double) -> String { СделкиФормат.деньги(Int(n.rounded())) }

    /// _cmpDocCss сайта в раскладке таблицами.
    private static let стиль = """
    body{font-family:-apple-system,"Helvetica Neue",Arial,sans-serif;color:#14201a;margin:0;font-size:12.5px;line-height:1.45}
    h1{margin:0;font-size:18px;color:#0d5c33}
    .top{width:100%;border-bottom:3px solid #12703f;margin-bottom:12px}
    .top td{border:0;padding:0 0 10px 0;vertical-align:top}
    .date{color:#5c6b62;font-size:12px;margin-top:3px}.form{font-size:11px;color:#6b7a72}
    .brand{text-align:right;font-weight:800;color:#12703f;font-size:14px}
    .base{font-size:12px;color:#3a463f;margin:0 0 10px}
    .parties{width:100%;border-collapse:separate;border-spacing:8px 0;margin:0 -8px 12px}
    .parties td{background:#f4f8f6;border:1px solid #e0ebe4;border-radius:10px;padding:9px 11px;vertical-align:top;width:50%}
    .cap{font-size:10px;text-transform:uppercase;letter-spacing:.04em;color:#5c6b62;margin-bottom:3px}
    .party b{font-size:13px}.party div{font-size:11.5px;color:#3a463f}
    table.it{width:100%;border-collapse:collapse;margin:6px 0 4px;font-size:12px}
    table.it th,table.it td{border:1px solid #dbe6df;padding:6px 8px;text-align:left}
    table.it th{background:#e7f6ee;color:#0d5c33;font-size:10px;text-transform:uppercase}
    .r{text-align:right}.c{text-align:center}
    table.tot{margin-left:auto;width:300px;margin-top:10px;border-collapse:collapse}
    table.tot td{padding:4px 0;font-size:12.5px;border:0}
    table.tot tr.grand td{border-top:2px solid #12703f;padding-top:8px;font-size:14.5px;color:#0d5c33;font-weight:800}
    .words{margin-top:12px;padding:9px 11px;background:#f4f8f6;border-radius:8px;font-size:12px;font-style:italic}
    .accept{margin-top:12px;padding:9px 11px;background:#e7f6ee;border:1px solid #d5e8dc;border-radius:8px;font-size:12px;color:#0d5c33;font-weight:600}
    table.sign{width:100%;margin-top:22px;border-collapse:separate;border-spacing:20px 0;margin-left:-20px}
    table.sign td{vertical-align:top;width:50%;border:0}
    .sl{border-top:1px solid #14201a;padding-top:5px;font-size:11.5px;color:#5c6b62;margin-top:14px}
    .mp{margin-top:8px;font-size:10.5px;color:#6b7a72}
    .pre{font-size:12px;line-height:1.6;margin:8px 0 4px}
    .cl h2{font-size:12.5px;margin:10px 0 4px;color:#0d5c33}.cl p{margin:0 0 5px;font-size:11.5px}
    .foot{margin-top:14px;padding:10px 12px;background:#e7f6ee;border:1px solid #d5e8dc;border-radius:10px;font-size:11.5px}
    .foot img{width:72px;height:72px;float:left;margin-right:10px}.foot b{color:#12703f;font-size:14px}
    """

    private static func страница(_ заголовок: String, _ тело: String) -> String {
        ["<!DOCTYPE html><html lang=\"ru\"><head><meta charset=\"utf-8\"><title>", экран(заголовок),
         "</title><style>", стиль, "</style></head><body>", тело, "</body></html>"].joined()
    }

    private static func шапка(_ заголовок: String, дата: String, форма: String, бренд: String) -> String {
        var левая = ["<h1>", экран(заголовок), "</h1><div class=\"date\">", дата, "</div>"].joined()
        if !форма.isEmpty { левая += "<div class=\"form\">" + форма + "</div>" }
        return ["<table class=\"top\"><tr><td>", левая, "</td><td class=\"brand\">", экран(бренд),
                "</td></tr></table>"].joined()
    }

    /// _cmpParty + _cmpReqLines.
    private static func сторона(_ подпись: String, _ с: [String: String]) -> String {
        var строки: [String] = ["<div class=\"cap\">" + подпись + "</div>", "<b>" + экран(с["name"] ?? "—") + "</b>"]
        if let бин = с["bin"] { строки.append("<div>БИН/ИИН " + экран(бин) + "</div>") }
        if let адрес = с["addr"] { строки.append("<div>" + экран(адрес) + "</div>") }
        var банк: [String] = []
        if let б = с["bank"] { банк.append("Банк: " + экран(б)) }
        if let б = с["bik"] { банк.append("БИК: " + экран(б)) }
        if let б = с["iik"] { банк.append("ИИК: " + экран(б)) }
        if let б = с["kbe"] { банк.append("Кбе: " + экран(б)) }
        if !банк.isEmpty { строки.append("<div>" + банк.joined(separator: " · ") + "</div>") }
        if let р = с["director"] { строки.append("<div>Рук.: " + экран(р) + "</div>") }
        return "<td class=\"party\">" + строки.joined() + "</td>"
    }

    private static func стороны(_ левая: String, _ л: [String: String], _ правая: String, _ п: [String: String]) -> String {
        "<table class=\"parties\"><tr>" + сторона(левая, л) + сторона(правая, п) + "</tr></table>"
    }

    private static func итоги(_ строки: [(String, String)], главная: (String, String)) -> String {
        var части = ["<table class=\"tot\">"]
        for (подпись, значение) in строки {
            части.append(["<tr><td>", подпись, "</td><td class=\"r\"><b>", значение, "</b></td></tr>"].joined())
        }
        части.append(["<tr class=\"grand\"><td>", главная.0, "</td><td class=\"r\">", главная.1, "</td></tr></table>"].joined())
        return части.joined()
    }

    private static func подписи(_ левая: String, _ л: String, _ правая: String, _ п: String, мп: String) -> String {
        let лЛиния = л.isEmpty ? "________________" : экран(л)
        let пЛиния = п.isEmpty ? "________________" : экран(п)
        return ["<table class=\"sign\"><tr><td><div class=\"cap\">", левая, "</div><div class=\"sl\">", лЛиния,
                " &nbsp;/&nbsp; подпись ___________</div><div class=\"mp\">", мп, "</div></td><td><div class=\"cap\">",
                правая, "</div><div class=\"sl\">", пЛиния, " &nbsp;/&nbsp; подпись ___________</div><div class=\"mp\">М.П.</div>",
                "</td></tr></table>"].joined()
    }

    private static func ставка(_ д: ДанныеДокумента) -> String {
        let с = д.ставка > 0 ? д.ставка : 16
        return с.rounded() == с ? String(Int(с)) : String(с)
    }

    // MARK: - Счёт на оплату (_cmpPrintInvoice)

    private static func счёт(_ д: ДанныеДокумента) -> String {
        let к = д.компания
        var дата = "от " + экран(д.дата)
        if !д.оплатитьДо.isEmpty { дата += " · <b>оплатить до " + экран(д.оплатитьДо) + "</b>" }
        var строки = ""
        for (i, п) in д.позиции.enumerated() {
            строки += ["<tr><td>", String(i + 1), "</td><td>", экран(п.название), "</td><td class=\"r\">",
                       экран(п.количество), "</td><td class=\"r\">", деньги(п.цена), "</td><td class=\"r\">",
                       деньги(п.сумма), " ₸</td></tr>"].joined()
        }
        var итог: [(String, String)] = [("Подытог", деньги(д.подытог) + " ₸")]
        if д.ндсЕсть { итог.append(("в т.ч. НДС " + ставка(д) + "%", деньги(д.ндс) + " ₸")) }
        let qr = картинкаQR("https://kliko.kz")
        var подвал = "<div class=\"foot\">"
        if !qr.isEmpty { подвал += "<img src=\"" + qr + "\" alt=\"QR\">" }
        подвал += "<b>Kliko.kz</b><div>Счёт сформирован на платформе kliko.kz — безопасные сделки под гарантом. "
        подвал += "Отсканируйте QR, чтобы перейти.</div><div style=\"clear:both\"></div></div>"
        let руководитель = к["director"].map { " — " + экран($0) } ?? " ______________"
        let бухгалтер = к["accountant"].map { " — " + экран($0) } ?? " ______________"
        return [шапка("Счёт на оплату № " + д.номер, дата: дата, форма: "", бренд: к["name"] ?? "Поставщик"),
                стороны("Поставщик", к, "Покупатель", д.покупатель),
                "<table class=\"it\"><thead><tr><th>№</th><th>Наименование</th><th class=\"r\">Кол-во</th>",
                "<th class=\"r\">Цена</th><th class=\"r\">Сумма</th></tr></thead><tbody>", строки, "</tbody></table>",
                итоги(итог, главная: ("Итого к оплате", деньги(д.итого) + " ₸")),
                "<div class=\"words\"><b>Сумма прописью:</b> ", экран(д.прописью), "</div>", подвал,
                "<table class=\"sign\"><tr><td><div class=\"sl\">Руководитель", руководитель,
                "</div></td><td><div class=\"sl\">Бухгалтер", бухгалтер, "</div></td></tr></table>"].joined()
    }

    // MARK: - Акт Р-1 (_cmpPrintAct)

    private static func акт(_ д: ДанныеДокумента) -> String {
        let к = д.компания
        var строки = ""
        for (i, п) in д.позиции.enumerated() {
            строки += ["<tr><td class=\"c\">", String(i + 1), "</td><td>", экран(п.название), "</td><td class=\"c\">усл.</td>",
                       "<td class=\"r\">", экран(п.количество), "</td><td class=\"r\">", деньги(п.цена), "</td><td class=\"r\">",
                       деньги(п.сумма), "</td></tr>"].joined()
        }
        let ндс: (String, String) = д.ндсЕсть ? ("в т.ч. НДС " + ставка(д) + "%", деньги(д.ндс) + " ₸") : ("НДС", "Без НДС")
        return [шапка("Акт выполненных работ (оказанных услуг) № " + д.номер, дата: "от " + экран(д.дата),
                      форма: "Форма Р-1", бренд: к["name"] ?? "Исполнитель"),
                "<div class=\"base\">Основание: договор № ____________ от ____________</div>",
                стороны("Исполнитель", к, "Заказчик", д.покупатель),
                "<table class=\"it\"><thead><tr><th class=\"c\">№</th><th>Наименование работ (услуг)</th><th class=\"c\">Ед.</th>",
                "<th class=\"r\">Кол-во</th><th class=\"r\">Цена</th><th class=\"r\">Стоимость</th></tr></thead><tbody>", строки,
                "</tbody></table>",
                итоги([("Подытог", деньги(д.подытог) + " ₸"), ндс], главная: ("Итого", деньги(д.итого) + " ₸")),
                "<div class=\"words\"><b>Сумма прописью:</b> ", экран(д.прописью), "</div>",
                "<div class=\"accept\">Работы (услуги) выполнены в полном объёме и в установленный срок. Заказчик претензий по ",
                "объёму, качеству и срокам оказания не имеет.</div>",
                подписи("Исполнитель (сдал)", к["director"] ?? "", "Заказчик (принял)", д.покупатель["director"] ?? "",
                        мп: "М.П.")].joined()
    }

    // MARK: - Накладная З-2 (_cmpPrintWaybill)

    private static func накладная(_ д: ДанныеДокумента) -> String {
        let к = д.компания
        let с = д.ндсЕсть ? (д.ставка > 0 ? д.ставка : 16) : 0
        var строки = ""
        for (i, п) in д.позиции.enumerated() {
            let налог: Double
            if !д.ндсЕсть {
                налог = 0
            } else if д.режим == "add" {
                налог = (п.сумма * с / 100).rounded()
            } else {
                налог = (п.сумма * с / (100 + с)).rounded()
            }
            let сНалогом = д.ндсЕсть && д.режим == "add" ? п.сумма + налог : п.сумма
            строки += ["<tr><td class=\"c\">", String(i + 1), "</td><td>", экран(п.название), "</td><td class=\"c\">шт</td>",
                       "<td class=\"r\">", экран(п.количество), "</td><td class=\"r\">", деньги(п.цена), "</td><td class=\"r\">",
                       деньги(налог), "</td><td class=\"r\">", деньги(сНалогом), "</td></tr>"].joined()
        }
        return [шапка("Накладная на отпуск запасов на сторону № " + д.номер, дата: "от " + экран(д.дата),
                      форма: "Форма З-2", бренд: к["name"] ?? "Поставщик"),
                "<div class=\"base\">Основание: договор № ____________ от ____________</div>",
                стороны("Организация-отправитель", к, "Организация-получатель", д.покупатель),
                "<table class=\"it\"><thead><tr><th class=\"c\">№</th><th>Наименование, характеристика</th><th class=\"c\">Ед.</th>",
                "<th class=\"r\">Кол-во</th><th class=\"r\">Цена</th><th class=\"r\">Сумма НДС</th><th class=\"r\">Сумма с НДС</th>",
                "</tr></thead><tbody>", строки, "</tbody></table>",
                итоги([("Всего наименований", String(д.позиции.count))], главная: ("Всего с НДС", деньги(д.итого) + " ₸")),
                "<div class=\"words\"><b>Всего отпущено на сумму (прописью):</b> ", экран(д.прописью), "</div>",
                подписи("Отпустил", к["director"] ?? "", "Получил (по доверенности)", д.покупатель["director"] ?? "",
                        мп: "Отпуск разрешил ___________ · Гл. бухгалтер ___________ · М.П.")].joined()
    }

    // MARK: - Договор поставки (_cmpPrintContract)

    private static func договор(_ д: ДанныеДокумента) -> String {
        let к = д.компания
        let п = д.покупатель
        let поставщик = экран(к["name"] ?? "Поставщик")
        let покупатель = экран(п["name"] ?? "Покупатель")
        var строки = ""
        for (i, поз) in д.позиции.enumerated() {
            строки += ["<tr><td class=\"c\">", String(i + 1), "</td><td>", экран(поз.название), "</td><td class=\"r\">",
                       экран(поз.количество), "</td><td class=\"r\">", деньги(поз.цена), "</td><td class=\"r\">",
                       деньги(поз.сумма), "</td></tr>"].joined()
        }
        let ндсТекст: String = д.ндсЕсть ? ["в том числе НДС ", ставка(д), "% — ", деньги(д.ндс), " ₸"].joined() : "без НДС"
        var итог: [(String, String)] = [("Подытог", деньги(д.подытог) + " ₸")]
        if д.ндсЕсть { итог.append(("НДС " + ставка(д) + "%", деньги(д.ндс) + " ₸")) }
        let вводная = [поставщик, к["director"].map { ", в лице руководителя " + экран($0) + "," } ?? "",
                       " именуемый в дальнейшем «Поставщик», с одной стороны, и ", покупатель,
                       п["director"].map { ", в лице " + экран($0) + "," } ?? "",
                       " именуемый в дальнейшем «Покупатель», с другой стороны, заключили настоящий Договор о нижеследующем:"]
        return [шапка("Договор поставки № " + (д.номер.isEmpty ? "____" : д.номер), дата: "от " + экран(д.дата),
                      форма: "г. " + экран(к["city"] ?? "Алматы"), бренд: к["name"] ?? "Поставщик"),
                "<div class=\"pre\">", вводная.joined(), "</div>",
                "<div class=\"cl\"><h2>1. Предмет договора</h2><p>1.1. Поставщик обязуется передать в собственность Покупателя ",
                "товар (продукцию) согласно спецификации ниже, а Покупатель — принять и оплатить его на условиях настоящего ",
                "Договора.</p></div>",
                "<table class=\"it\"><thead><tr><th class=\"c\">№</th><th>Наименование (спецификация)</th><th class=\"r\">Кол-во</th>",
                "<th class=\"r\">Цена, ₸</th><th class=\"r\">Сумма, ₸</th></tr></thead><tbody>", строки, "</tbody></table>",
                итоги(итог, главная: ("Итого", деньги(д.итого) + " ₸")),
                "<div class=\"words\"><b>Сумма договора прописью:</b> ", экран(д.прописью), "</div>",
                "<div class=\"cl\"><h2>2. Цена и порядок расчётов</h2><p>2.1. Общая стоимость товара составляет ",
                деньги(д.итого), " ₸ (", ндсТекст, ").</p><p>2.2. Оплата производится в безналичном порядке на основании счёта ",
                "на оплату в течение 5 (пяти) рабочих дней с момента его выставления, если иное не согласовано сторонами.</p></div>",
                "<div class=\"cl\"><h2>3. Условия поставки</h2><p>3.1. Срок и способ поставки согласовываются сторонами. Право ",
                "собственности и риски переходят к Покупателю с момента передачи товара и подписания накладной.</p></div>",
                "<div class=\"cl\"><h2>4. Ответственность сторон</h2><p>4.1. За нарушение сроков оплаты или поставки виновная ",
                "сторона уплачивает пеню 0,1% от суммы обязательства за каждый день просрочки, но не более 10%.</p><p>4.2. В ",
                "остальном стороны несут ответственность в соответствии с законодательством Республики Казахстан.</p></div>",
                "<div class=\"cl\"><h2>5. Срок действия</h2><p>5.1. Договор вступает в силу с момента подписания и действует до ",
                "полного исполнения сторонами обязательств.</p><p>5.2. Все споры разрешаются путём переговоров, а при ",
                "недостижении согласия — в суде по месту нахождения ответчика.</p></div>",
                "<div class=\"cl\"><h2>6. Реквизиты и подписи сторон</h2></div>",
                стороны("Поставщик", к, "Покупатель", п),
                подписи("Поставщик", к["director"] ?? "", "Покупатель", п["director"] ?? "", мп: "М.П.")].joined()
    }

    // MARK: - Доверенность М-2а (_cmpPrintPOA)

    private static func доверенность(_ д: ДанныеДокумента) -> String {
        let к = д.компания
        let п = д.покупатель
        let организация = экран(п["name"] ?? "Организация")
        let поставщик = экран(к["name"] ?? "Поставщик")
        let лицо = д.лицо.trimmingCharacters(in: .whitespaces)
        let документ = д.удостоверение.trimmingCharacters(in: .whitespaces)
        let кому = лицо.isEmpty ? "<b>________________________________</b> (ФИО)" : "<b>" + экран(лицо) + "</b>"
        let удостоверение = документ.isEmpty ? "удостоверение личности № __________" : "удостоверение личности " + экран(документ)
        var строки = ""
        for (i, поз) in д.позиции.enumerated() {
            строки += ["<tr><td class=\"c\">", String(i + 1), "</td><td>", экран(поз.название),
                       "</td><td class=\"c\">шт</td><td class=\"r\">", экран(поз.количество), "</td></tr>"].joined()
        }
        var лицоСтрока = ""
        if !лицо.isEmpty {
            лицоСтрока = "<div class=\"words\" style=\"font-style:normal\"><b>Доверенное лицо:</b> " + экран(лицо)
                + (документ.isEmpty ? "" : " · " + экран(документ)) + "</div>"
        }
        let номер = экран(д.номер.isEmpty ? "____" : д.номер)
        return [шапка("Доверенность № " + (д.номер.isEmpty ? "____" : д.номер), дата: "от " + экран(д.дата),
                      форма: "Форма М-2а · действительна по ____________", бренд: п["name"] ?? "Организация"),
                стороны("Организация (доверитель)", п, "Поставщик (от кого получить)", к), лицоСтрока,
                "<div class=\"pre\">Настоящей доверенностью ", организация, " доверяет ", кому, ", ", удостоверение,
                ", получить от ", поставщик, " по счёту/накладной № ", номер, " от ", экран(д.дата),
                " следующие товарно-материальные ценности:</div>",
                "<table class=\"it\"><thead><tr><th class=\"c\">№</th><th>Наименование ТМЦ</th><th class=\"c\">Ед.</th>",
                "<th class=\"r\">Кол-во</th></tr></thead><tbody>", строки, "</tbody></table>",
                "<div class=\"words\"><b>Всего наименований:</b> ", String(д.позиции.count), " &nbsp;·&nbsp; <b>Сумма:</b> ",
                деньги(д.итого), " ₸ (", экран(д.прописью), ")</div>",
                "<div class=\"cl\"><p>Доверенность действительна _____ дней. Образец подписи доверенного лица ",
                "____________________ удостоверяем.</p></div>",
                подписи("Руководитель", п["director"] ?? "", "Главный бухгалтер", "", мп: "М.П.")].joined()
    }

    // MARK: - Сумма прописью (_cmpNum2Words)

    static func прописью(_ сумма: Int) -> String {
        let n = max(0, сумма)
        if n == 0 { return "Ноль тенге 00 тиын" }
        let единицы = ["", "один", "два", "три", "четыре", "пять", "шесть", "семь", "восемь", "девять", "десять", "одиннадцать",
                       "двенадцать", "тринадцать", "четырнадцать", "пятнадцать", "шестнадцать", "семнадцать", "восемнадцать",
                       "девятнадцать"]
        let десятки = ["", "", "двадцать", "тридцать", "сорок", "пятьдесят", "шестьдесят", "семьдесят", "восемьдесят",
                       "девяносто"]
        let сотни = ["", "сто", "двести", "триста", "четыреста", "пятьсот", "шестьсот", "семьсот", "восемьсот", "девятьсот"]
        func тройка(_ x: Int, женский: Bool) -> String {
            var слова: [String] = []
            if x / 100 > 0 { слова.append(сотни[x / 100]) }
            let о = x % 100
            if о > 0 && о < 20 {
                слова.append(женский && о == 1 ? "одна" : (женский && о == 2 ? "две" : единицы[о]))
            } else if о >= 20 {
                слова.append(десятки[о / 10])
                let е = о % 10
                if е > 0 { слова.append(женский && е == 1 ? "одна" : (женский && е == 2 ? "две" : единицы[е])) }
            }
            return слова.joined(separator: " ")
        }
        func форма(_ x: Int, _ ф: [String]) -> String {
            let о = x % 100
            if о >= 11 && о <= 14 { return ф[2] }
            let е = x % 10
            if е == 1 { return ф[0] }
            if е >= 2 && е <= 4 { return ф[1] }
            return ф[2]
        }
        var части: [String] = []
        let миллионы = (n / 1_000_000) % 1000
        let тысячи = (n / 1000) % 1000
        let остаток = n % 1000
        if миллионы > 0 {
            части.append(тройка(миллионы, женский: false))
            части.append(форма(миллионы, ["миллион", "миллиона", "миллионов"]))
        }
        if тысячи > 0 {
            части.append(тройка(тысячи, женский: true))
            части.append(форма(тысячи, ["тысяча", "тысячи", "тысяч"]))
        }
        if остаток > 0 { части.append(тройка(остаток, женский: false)) }
        let строка = части.joined(separator: " ").split(separator: " ").joined(separator: " ")
        guard let первая = строка.first else { return "Ноль тенге 00 тиын" }
        let хвост = String(строка.dropFirst())
        return "\(String(первая).uppercased())\(хвост) тенге 00 тиын"
    }

    // MARK: - QR

    /// QR-код адреса картинкой PNG в data URL (CoreImage), как _cmpQrDataURL сайта. Не вышло — пусто.
    static func картинкаQR(_ текст: String) -> String {
        guard let фильтр = CIFilter(name: "CIQRCodeGenerator") else { return "" }
        фильтр.setValue(Data(текст.utf8), forKey: "inputMessage")
        фильтр.setValue("M", forKey: "inputCorrectionLevel")
        guard let код = фильтр.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return "" }
        let контекст = CIContext()
        guard let картинка = контекст.createCGImage(код, from: код.extent),
              let png = UIImage(cgImage: картинка).pngData() else { return "" }
        return "data:image/png;base64," + png.base64EncodedString()
    }
}
