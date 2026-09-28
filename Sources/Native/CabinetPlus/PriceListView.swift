import SwiftUI
import UIKit
import UniformTypeIdentifiers

/**
 «ГЕНЕРАТОР ПРАЙС-ЛИСТА» — СВОИМ ЭКРАНОМ (priceListOpen модуля js/cabinet-business.min.js; владелец: «кабинет полностью
 SwiftUI»). Пункт «Прайс-лист» группы «Для бизнеса». За PRO, как proGate("pricelist").

   · POST cabinet.php?action=price_data {csrf} → {ok, company{name, bin, director, addr, phone, iik, bank, bik}, items[{art,
     name, price, qty, cond, photo, url, kind}], date, accent, store_url} | need_pro;
   · настройки — как у сайта: тип (товары / услуги), вид цены (розничная, спец, опт, дилер, своя колонка), корректировка
     в процентах (−95…500, шаг 5), НДС (без / в т.ч. / сверху + ставка), цветовая схема (_PL_SCHEMES и «Без»), колонки
     (фото, артикул, состояние, кол-во, ссылки, QR на витрину, банковские реквизиты), выбор позиций с поиском;
   · «Скачать PDF» — своя разметка _plHtml (таблицей) → ОкноДокумента (PDF, «Поделиться», «Печать»); фото позиций
     скачиваются и встраиваются в документ картинками, QR витрины — CoreImage;
   · «Отправить по БИН» — price_send {csrf, bin, title, html}: ok — «Прайс-лист доставлен в кабинет контрагента»,
     no_account — «Организация с этим БИН ещё не зарегистрирована…» и ссылка;
   · «Поделиться» — doc_share_link {csrf, title, html, minutes: 15 | 60 | 1440} → url, системный лист;
   · «Загрузить обновлённый» — price_import (файл прайса multipart) → «Обновлено цен/остатков: N».
 */
struct ПозицияПрайса: Identifiable, Equatable {
    let id: String
    let название: String
    let цена: Double
    let количество: String
    let состояние: String
    let фото: String
    let ссылка: String
    let вид: String
}

@MainActor
final class ПрайсЛистМодель: ObservableObject {
    enum Состояние: Equatable { case идёт, готово, нуженВход, нуженПРО, ошибка(String) }

    @Published private(set) var состояние: Состояние = .идёт
    @Published private(set) var позиции: [ПозицияПрайса] = []
    @Published private(set) var компания: [String: String] = [:]
    @Published private(set) var дата = ""
    @Published private(set) var витрина = ""
    @Published var вид = "goods"
    @Published var видЦены = "retail"
    @Published var своя = ""
    @Published var процент: Double = 0
    @Published var ндс = "without"
    @Published var ставкаНДС: Double = 12
    @Published var акцент = "#16a34a"
    @Published var фото = true
    @Published var артикул = true
    @Published var состояниеКолонка = true
    @Published var количество = true
    @Published var ссылки = true
    @Published var qr = true
    @Published var реквизиты = false
    @Published var снято: Set<String> = []
    @Published var поиск = ""
    @Published var занято = false
    @Published private(set) var плашка: String? = nil
    private var скрыть: Task<Void, Never>? = nil

    static let схемы = ["#16a34a", "#2563eb", "#4f46e5", "#0d9488", "#7c3aed", "#dc2626", "#ea580c", "#334155"]

    private func т(_ ключ: String) -> String { КабинетПлюсText.т(ключ) }

    func показать(_ текст: String) {
        withAnimation(.easeOut(duration: 0.2)) { плашка = текст }
        UIAccessibility.post(notification: .announcement, argument: текст)
        скрыть?.cancel()
        скрыть = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { self?.плашка = nil }
        }
    }

    func загрузить() async {
        do {
            let j = try await ЗапросыКабинета.отправить("cabinet.php?action=price_data", [:])
            typealias A = МоиОбъявленияAPI
            var к: [String: String] = [:]
            for (ключ, значение) in (j["company"] as? [String: Any]) ?? [:] {
                let т = A.строка(значение)
                if !т.isEmpty { к[ключ] = т }
            }
            компания = к
            дата = A.строка(j["date"])
            витрина = A.строка(j["store_url"])
            позиции = ((j["items"] as? [Any]) ?? []).compactMap { запись -> ПозицияПрайса? in
                guard let п = запись as? [String: Any] else { return nil }
                let вид = A.строка(п["kind"])
                return ПозицияПрайса(id: A.строка(п["art"]), название: A.строка(п["name"]), цена: A.число(п["price"]),
                                     количество: п["qty"] == nil || п["qty"] is NSNull ? "—" : A.строка(п["qty"]),
                                     состояние: A.строка(п["cond"]), фото: A.строка(п["photo"]), ссылка: A.строка(п["url"]),
                                     вид: вид.isEmpty ? "goods" : вид)
            }
            let цвет = A.строка(j["accent"])
            if цвет.range(of: "^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$", options: .regularExpression) != nil { акцент = цвет }
            if к["iik"] != nil || к["bank"] != nil { реквизиты = true }
            состояние = .готово
        } catch let с as ЗапросыКабинета.Сбой {
            состояние = с.нуженВход ? .нуженВход : (с.нуженПРО ? .нуженПРО : .ошибка(с.текст))
        } catch {
            состояние = .ошибка(т("no_conn"))
        }
    }

    var вВиде: [ПозицияПрайса] { позиции.filter { $0.вид == вид } }

    var найдено: [ПозицияПрайса] {
        let q = поиск.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return вВиде }
        return вВиде.filter { ($0.название + " " + $0.id).lowercased().contains(q) }
    }

    var выбранные: [ПозицияПрайса] { вВиде.filter { !снято.contains($0.id) } }

    /// _plPrice: корректировка в процентах, «сверху» — ещё и НДС.
    func цена(_ базовая: Double) -> Double {
        var n = (базовая * (1 + процент / 100)).rounded()
        if ндс == "top" { n = (n * (1 + ставкаНДС / 100)).rounded() }
        return n
    }

    var подписьЦены: String {
        if видЦены == "custom" {
            let с = своя.trimmingCharacters(in: .whitespaces)
            return с.isEmpty ? т("pl_pt_custom") : с
        }
        let ключи = ["retail": "pl_pt_retail", "special": "pl_pt_special", "opt": "pl_pt_opt", "dealer": "pl_pt_dealer"]
        return т(ключи[видЦены] ?? "pl_col_price")
    }

    var заметкаНДС: String {
        let с = ставкаНДС.rounded() == ставкаНДС ? String(Int(ставкаНДС)) : String(ставкаНДС)
        switch ндс {
        case "incl": return "\(т("pl_vat_incl_p")) \(с)%)"
        case "top": return "\(т("pl_vat_top_p")) \(с)% (\(т("pl_vat_added")))"
        default: return т("pl_vat_note_without")
        }
    }

    var подсказкаПроцента: String {
        if процент > 0 { return "+\(Int(процент))% \(т("pl_markup"))" }
        if процент < 0 { return "\(Int(процент))% \(т("pl_discount"))" }
        return т("pl_base")
    }

    var заголовок: String {
        let вид = т(self.вид == "service" ? "dtype_serv" : "dtype_goods")
        return "\(т("pl_title")) · \(вид) · \(дата)"
    }

    // MARK: - Разметка (_plHtml)

    /// Разметка прайс-листа. картинки — адрес фото → data URL (скачанные заранее).
    func разметка(картинки: [String: String]) -> String {
        let э = ДокументыБизнеса.экран
        let без = акцент == "none"
        let цвет = без ? "#334155" : акцент
        let показатьСостояние = состояниеКолонка && вид != "service"
        var строки = ""
        for п in выбранные {
            var ряд = "<tr>"
            if фото {
                if let картинка = картинки[п.фото] {
                    ряд += "<td class=\"ph\"><img class=\"pl-ph\" src=\"" + картинка + "\"></td>"
                } else {
                    ряд += "<td class=\"ph\"></td>"
                }
            }
            if артикул { ряд += "<td class=\"art\">" + э(п.id) + "</td>" }
            var имя = э(п.название)
            if ссылки && !п.ссылка.isEmpty { имя = ["<a href=\"", э(п.ссылка), "\">", имя, "</a>"].joined() }
            ряд += "<td>" + имя + "</td>"
            if показатьСостояние {
                let с = п.состояние == "new" ? т("cond_new") : (п.состояние == "used" ? т("cond_used") : "—")
                ряд += "<td class=\"c\">" + с + "</td>"
            }
            if количество { ряд += "<td class=\"c\">" + э(п.количество) + "</td>" }
            ряд += "<td class=\"r\">" + ДокументыБизнеса.деньги(цена(п.цена)) + " ₸</td></tr>"
            строки += ряд
        }
        if строки.isEmpty { строки = "<tr><td class=\"empty\" colspan=\"4\">" + т("pl_empty") + "</td></tr>" }
        var шапкаТаблицы = "<tr>"
        if фото { шапкаТаблицы += "<th class=\"ph\">" + т("pl_col_photo") + "</th>" }
        if артикул { шапкаТаблицы += "<th class=\"art\">" + т("pl_col_art") + "</th>" }
        шапкаТаблицы += "<th>" + т("pl_col_name") + "</th>"
        if показатьСостояние { шапкаТаблицы += "<th class=\"c\">" + т("pl_col_cond") + "</th>" }
        if количество { шапкаТаблицы += "<th class=\"c\">" + т("pl_col_qty") + "</th>" }
        шапкаТаблицы += "<th class=\"r\">" + э(подписьЦены) + "</th></tr>"
        let к = компания
        var первая: [String] = []
        if let бин = к["bin"] { первая.append(т("pl_bin") + " " + э(бин)) }
        if let рук = к["director"] { первая.append(т("pl_director") + " " + э(рук)) }
        var вторая: [String] = []
        if let адрес = к["addr"] { вторая.append(э(адрес)) }
        if let тел = к["phone"] { вторая.append(э(тел)) }
        var банк: [String] = []
        if let иик = к["iik"] { банк.append(т("pl_iik") + " " + э(иик)) }
        if let б = к["bank"] { банк.append(э(б)) }
        if let бик = к["bik"] { банк.append(т("pl_bik") + " " + э(бик)) }
        var левая = "<div class=\"nm\">" + э(к["name"] ?? "—") + "</div>"
        if !первая.isEmpty { левая += "<div class=\"m\">" + первая.joined(separator: " · ") + "</div>" }
        if !вторая.isEmpty { левая += "<div class=\"m\">" + вторая.joined(separator: " · ") + "</div>" }
        if реквизиты && !банк.isEmpty { левая += "<div class=\"m\">" + банк.joined(separator: " · ") + "</div>" }
        let видТекст = т(вид == "service" ? "dtype_serv" : "dtype_goods")
        var правая = ""
        if qr && !витрина.isEmpty {
            let код = ДокументыБизнеса.картинкаQR(витрина)
            if !код.isEmpty { правая += "<img class=\"qr\" src=\"" + код + "\">" }
        }
        правая += ["<div class=\"cap\">", т("pl_title"), " · ", э(видТекст), "<span>", т("pl_as_of"), " ", э(дата),
                   "</span></div>"].joined()
        let фон = без ? "#ffffff" : цвет
        let текстШапки = без ? "#14201a" : "#ffffff"
        let светлый = ПрайсЛистМодель.светлее(цвет)
        let тёмный = ПрайсЛистМодель.темнее(цвет)
        let стиль = [
            "body{font-family:-apple-system,Arial,sans-serif;color:#14201a;margin:0;font-size:12.5px}",
            "table.h{width:100%;background:", фон, ";color:", текстШапки, ";border-radius:12px;margin-bottom:14px;",
            без ? "border:1px solid #e2e8f0;border-bottom:3px solid #334155;" : "", "}",
            "table.h td{padding:14px 18px;vertical-align:top;border:0}",
            ".nm{font-size:19px;font-weight:800}.m{font-size:11px;margin-top:3px}",
            ".qr{width:62px;height:62px;background:#fff;border-radius:6px;padding:3px;float:right;margin-left:10px}",
            ".cap{text-align:right;font-size:13px;font-weight:800}.cap span{display:block;font-size:10.5px;font-weight:500}",
            "table.plt{width:100%;border-collapse:collapse;font-size:12px}",
            ".plt th,.plt td{border:1px solid #dce7e0;padding:7px 9px;text-align:left;vertical-align:top}",
            ".plt th{background:", светлый, ";color:", тёмный, ";font-size:10px;text-transform:uppercase}",
            ".plt td.r,.plt th.r{text-align:right;white-space:nowrap;font-weight:600}.plt td.c,.plt th.c{text-align:center}",
            ".plt td.art{color:#6b7a72;font-size:11px;white-space:nowrap}.plt td.ph,.plt th.ph{width:48px;text-align:center;padding:4px}",
            ".pl-ph{width:40px;height:40px;border-radius:6px}.plt a{color:", тёмный, ";text-decoration:none}",
            ".empty{text-align:center;color:#6b7a72;padding:18px}",
            ".vat{margin-top:10px;font-size:11px;font-weight:700;color:", тёмный, "}",
            ".f{margin-top:10px;font-size:10px;color:#6b7a72}"
        ].joined()
        let ндсСтрока = "<div class=\"vat\">" + э(заметкаНДС) + "</div>"
        let подвал = ["<div class=\"f\">", т("pl_footer"), " · ", э(дата), " — ", т("pl_footer2"), "</div>"].joined()
        return ["<!DOCTYPE html><html lang=\"ru\"><head><meta charset=\"utf-8\"><title>", э(заголовок), "</title><style>",
                стиль, "</style></head><body><table class=\"h\"><tr><td>", левая, "</td><td>", правая, "</td></tr></table>",
                "<table class=\"plt\"><thead>", шапкаТаблицы, "</thead><tbody>", строки, "</tbody></table>", ндсСтрока, подвал,
                "</body></html>"].joined()
    }

    /// Фото выбранных позиций (до 80) — data URL уменьшенных картинок: печать не качает картинки сама.
    func картинки() async -> [String: String] {
        guard фото else { return [:] }
        let адреса = Array(Set(выбранные.map(\.фото).filter { !$0.isEmpty }).prefix(80))
        var итог: [String: String] = [:]
        await withTaskGroup(of: (String, String?).self) { группа in
            for адрес in адреса {
                группа.addTask {
                    guard let url = await ЗапросыКабинета.картинка(адрес),
                          let пара = try? await URLSession.shared.data(from: url),
                          let картинка = UIImage(data: пара.0) else { return (адрес, nil) }
                    let сторона: CGFloat = 96
                    let масштаб = min(1, сторона / max(картинка.size.width, картинка.size.height, 1))
                    let размер = CGSize(width: max(1, картинка.size.width * масштаб), height: max(1, картинка.size.height * масштаб))
                    let формат = UIGraphicsImageRendererFormat.default()
                    формат.scale = 1
                    let уменьшенная = UIGraphicsImageRenderer(size: размер, format: формат).image { _ in
                        картинка.draw(in: CGRect(origin: .zero, size: размер))
                    }
                    guard let jpeg = уменьшенная.jpegData(compressionQuality: 0.75) else { return (адрес, nil) }
                    return (адрес, "data:image/jpeg;base64," + jpeg.base64EncodedString())
                }
            }
            for await (адрес, данные) in группа {
                if let данные { итог[адрес] = данные }
            }
        }
        return итог
    }

    // MARK: - Действия

    func pdf() {
        guard !выбранные.isEmpty else {
            показать(т("pl_empty"))
            return
        }
        guard !занято else { return }
        занято = true
        Task { @MainActor in
            let фото = await self.картинки()
            self.занято = false
            ОкнаДокументов.показать(ДокументКабинета(заголовок: self.заголовок,
                                                     источник: .разметка(self.разметка(картинки: фото))))
        }
    }

    /// _plDoSend: БИН — 12 цифр; no_account — ссылка вместо доставки.
    func отправить(бин: String, итог: @escaping (String, Bool, Bool) -> Void) {
        let цифры = бин.filter { $0.isASCII && $0.isNumber }
        guard !выбранные.isEmpty else {
            итог(т("pl_empty"), false, false)
            return
        }
        guard цифры.count == 12 else {
            итог(т("pl_bin_err"), false, false)
            return
        }
        guard !занято else { return }
        занято = true
        Task { @MainActor in
            defer { self.занято = false }
            let фото = await self.картинки()
            do {
                let j = try await МоиОбъявленияAPI.отправить("cabinet.php?action=price_send",
                                                           тело: ["bin": цифры, "title": self.заголовок,
                                                                  "html": self.разметка(картинки: фото)])
                if МоиОбъявленияAPI.да(j["ok"]) {
                    итог(self.т("pl_sent"), true, false)
                } else if МоиОбъявленияAPI.да(j["no_account"]) {
                    итог(self.т("docshare_notreg"), false, true)
                } else {
                    итог(ЗапросыКабинета.текстОшибки(j), false, false)
                }
            } catch {
                итог(self.т("no_conn"), false, false)
            }
        }
    }

    /// cmpShareGen: ссылка на документ на minutes минут.
    func ссылка(минут: Int, готово: @escaping (URL?) -> Void) {
        guard !выбранные.isEmpty else {
            показать(т("pl_empty"))
            return
        }
        guard !занято else { return }
        занято = true
        Task { @MainActor in
            defer { self.занято = false }
            let фото = await self.картинки()
            let адрес = await СсылкаНаДокумент.создать(заголовок: self.заголовок, разметка: self.разметка(картинки: фото),
                                                       минут: минут, ошибка: { self.показать($0) })
            готово(адрес)
        }
    }

    /// priceImport: файл обновлённого прайса → «Обновлено цен/остатков: N».
    func загрузитьОбновлённый(_ адрес: URL) {
        guard !занято else { return }
        занято = true
        Task { @MainActor in
            defer { self.занято = false }
            let доступ = адрес.startAccessingSecurityScopedResource()
            defer { if доступ { адрес.stopAccessingSecurityScopedResource() } }
            guard let данные = try? Data(contentsOf: адрес), !данные.isEmpty else {
                self.показать(self.т("err_generic"))
                return
            }
            let тип = UTType(filenameExtension: адрес.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            let файл = ИмпортAPI.Файл(поле: "file", имя: адрес.lastPathComponent, тип: тип,
                                      base64: данные.base64EncodedString())
            do {
                guard let j = try await ИмпортAPI.форма("cabinet.php?action=price_import", поля: [:], файл: файл) else {
                    self.показать(self.т("err_generic"))
                    return
                }
                if МоиОбъявленияAPI.да(j["ok"]) {
                    self.показать("\(self.т("pl_updated")): \(МоиОбъявленияAPI.целое(j["updated"]))")
                } else {
                    self.показать(ЗапросыКабинета.текстОшибки(j))
                }
            } catch {
                self.показать(self.т("no_conn"))
            }
        }
    }

    // MARK: - Краски (_plTint, _plDark)

    private static func rgb(_ hex: String) -> (Double, Double, Double) {
        var s = hex.replacingOccurrences(of: "#", with: "")
        if s.count == 3 { s = s.map { String(repeating: String($0), count: 2) }.joined() }
        let n = Int(s, radix: 16) ?? 0x16a34a
        return (Double((n >> 16) & 255), Double((n >> 8) & 255), Double(n & 255))
    }

    static func светлее(_ hex: String) -> String {
        let (r, g, b) = rgb(hex)
        func к(_ x: Double) -> Int { Int((x + 0.88 * (255 - x)).rounded()) }
        return "rgb(\(к(r)),\(к(g)),\(к(b)))"
    }

    static func темнее(_ hex: String) -> String {
        let (r, g, b) = rgb(hex)
        return "rgb(\(Int((0.5 * r).rounded())),\(Int((0.5 * g).rounded())),\(Int((0.5 * b).rounded())))"
    }

    static func цвет(_ hex: String) -> Color {
        let (r, g, b) = rgb(hex)
        return Color(red: r / 255, green: g / 255, blue: b / 255)
    }
}

/// doc_share_link — ссылка на документ на время (15 мин, 1 ч, 24 ч).
@MainActor
enum СсылкаНаДокумент {
    static func создать(заголовок: String, разметка: String, минут: Int, ошибка: (String) -> Void) async -> URL? {
        do {
            let j = try await ЗапросыКабинета.отправить("cabinet.php?action=doc_share_link",
                                                        ["title": заголовок, "html": разметка, "minutes": минут])
            guard let адрес = URL(string: МоиОбъявленияAPI.строка(j["url"])) else {
                ошибка(КабинетПлюсText.т("err_generic"))
                return nil
            }
            return адрес
        } catch {
            ошибка(ЗапросыКабинета.текст(error))
            return nil
        }
    }
}

/// Ссылка для системного листа «Поделиться» (item для .sheet).
struct СсылкаДляЛиста: Identifiable {
    let id = UUID()
    let адрес: URL
    let текст: String
}

/// Системный лист «Поделиться» (UIActivityViewController) для SwiftUI .sheet.
struct ЛистПоделитьсяКабинета: UIViewControllerRepresentable {
    let предметы: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: предметы, applicationActivities: nil)
    }

    func updateUIViewController(_ контроллер: UIActivityViewController, context: Context) {}
}

struct ЭкранПрайсЛиста: View {
    let открыть: (URL) -> Void

    @StateObject private var модель = ПрайсЛистМодель()
    @State private var бин = ""
    @State private var отправкаОткрыта = false
    @State private var итогОтправки: String? = nil
    @State private var хорошо = false
    @State private var поделиться: СсылкаДляЛиста? = nil
    @State private var выборФайла = false
    @State private var входОткрыт = false

    private func т(_ ключ: String) -> String { КабинетПлюсText.т(ключ) }

    var body: some View {
        Group {
            switch модель.состояние {
            case .идёт:
                ЗагрузкаБизнеса()
            case .нуженВход:
                ПустоСайта(значок: "person.crop.circle", заголовок: CabinetText.т("signed_out"),
                           подпись: CabinetText.т("signed_out_sub"), кнопка: CabinetText.т("login"),
                           действие: { входОткрыт = true })
            case .нуженПРО:
                ScrollView {
                    КарточкаБизнеса(БизнесРазделыText.т("pro_need"), значок: "crown") {
                        Text(БизнесРазделыText.т("pro_need_s"))
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.текстВторой)
                        ЦифроваяПокупка()
                    }
                    .padding(12)
                }
            case .ошибка(let текст):
                ПустоСайта(значок: "wifi.exclamationmark", заголовок: текст, кнопка: т("retry"),
                           действие: { Task { await модель.загрузить() } })
            case .готово:
                содержимое
            }
        }
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .navigationTitle(т("pl_gen_title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await модель.загрузить() }
        .overlay(alignment: .bottom) {
            if let текст = модель.плашка { ПлашкаКошелька(текст: текст) }
        }
        .sheet(item: $поделиться) { с in
            ЛистПоделитьсяКабинета(предметы: [с.текст, с.адрес])
        }
        .sheet(isPresented: $входОткрыт) {
            ЭкранВхода(eGovВключён: true, открыть: { ПереходыКабинета.открыть($0) }, вошли: {
                Task { await модель.загрузить() }
            })
        }
        .fileImporter(isPresented: $выборФайла,
                      allowedContentTypes: [.commaSeparatedText, .spreadsheet, .data, .xml, .plainText]) { итог in
            if case .success(let адрес) = итог { модель.загрузитьОбновлённый(адрес) }
        }
    }

    private var содержимое: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                настройки
                колонки
                позиции
                действия
            }
            .padding(12)
        }
    }

    // MARK: Настройки

    private var настройки: some View {
        КарточкаБизнеса(т("pl_gen_title"), значок: "slider.horizontal.3") {
            видИЦена
            ндсИСхема
        }
    }

    @ViewBuilder
    private var видИЦена: some View {
        подпись(т("pl_kind"))
        ВкладкиРаздела(варианты: [("goods", т("dtype_goods")), ("service", т("dtype_serv"))], выбрано: $модель.вид)
        подпись(т("pl_price_type"))
        ВкладкиРаздела(варианты: [("retail", т("pl_pt_retail_s")), ("special", т("pl_pt_special_s")),
                                  ("opt", т("pl_pt_opt_s")), ("dealer", т("pl_pt_dealer_s")),
                                  ("custom", т("pl_pt_custom_s"))], выбрано: $модель.видЦены)
        if модель.видЦены == "custom" {
            TextField(т("pl_custom_ph"), text: $модель.своя)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(т("pl_custom_name"))
        }
        подпись(т("pl_adjust"))
        Stepper(value: $модель.процент, in: -95...500, step: 5) {
            HStack {
                Text("\(Int(модель.процент)) %")
                    .font(.system(size: 15, weight: .bold))
                    .monospacedDigit()
                Text(модель.подсказкаПроцента)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.текстВторой)
            }
        }
    }

    @ViewBuilder
    private var ндсИСхема: some View {
        подпись(т("pl_vat"))
        ВкладкиРаздела(варианты: [("without", т("pl_vat_without")), ("incl", т("pl_vat_incl")), ("top", т("pl_vat_top"))],
                       выбрано: $модель.ндс)
        if модель.ндс != "without" {
            Stepper(value: $модель.ставкаНДС, in: 0...100, step: 1) {
                Text("\(т("pl_vat_rate")): \(Int(модель.ставкаНДС)) %")
                    .font(.system(size: 14))
            }
            Text(модель.заметкаНДС)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.текстВторой)
        }
        подпись(т("pl_scheme"))
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(схемы, id: \.self) { цвет in
                    Button {
                        модель.акцент = цвет
                    } label: {
                        ZStack {
                            if цвет == "none" {
                                Circle().strokeBorder(Theme.линия, lineWidth: 1.5)
                                Text(т("pl_scheme_none_s"))
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Theme.текстВторой)
                            } else {
                                Circle().fill(ПрайсЛистМодель.цвет(цвет))
                            }
                            if модель.акцент == цвет {
                                Circle().strokeBorder(Theme.текст, lineWidth: 2.5).padding(-4)
                            }
                        }
                        .frame(width: 30, height: 30)
                        .padding(4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(цвет == "none" ? т("pl_scheme_none") : цвет)
                    .accessibilityAddTraits(модель.акцент == цвет ? .isSelected : [])
                }
            }
        }
    }

    private var схемы: [String] {
        var список = ПрайсЛистМодель.схемы
        if модель.акцент != "none" && !список.contains(модель.акцент) { список.insert(модель.акцент, at: 0) }
        список.append("none")
        return список
    }

    private var колонки: some View {
        КарточкаБизнеса(т("pl_columns"), значок: "tablecells") {
            Toggle(т("pl_col_photo"), isOn: $модель.фото)
            Toggle(т("pl_col_art"), isOn: $модель.артикул)
            Toggle(т("pl_col_cond"), isOn: $модель.состояниеКолонка)
                .disabled(модель.вид == "service")
            Toggle(т("pl_col_qty"), isOn: $модель.количество)
            Toggle(т("pl_links"), isOn: $модель.ссылки)
            Toggle(т("pl_qr"), isOn: $модель.qr)
            Toggle(т("pl_req"), isOn: $модель.реквизиты)
        }
        .tint(Theme.акцент)
    }

    // MARK: Позиции

    private var позиции: some View {
        КарточкаБизнеса("\(т("pl_pick")) \(модель.выбранные.count) / \(модель.вВиде.count)", значок: "checklist") {
            TextField(т("pl_search"), text: $модель.поиск)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button(т("pl_all")) { модель.снято.subtract(модель.вВиде.map(\.id)) }
                Spacer()
                Button(т("pl_none")) { модель.снято.formUnion(модель.вВиде.map(\.id)) }
            }
            .font(.system(size: 14, weight: .semibold))
            .tint(Theme.акцент)
            if модель.найдено.isEmpty {
                Text(т("pl_empty"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
            }
            ForEach(модель.найдено) { п in
                Toggle(isOn: Binding(get: { !модель.снято.contains(п.id) }, set: { да in
                    if да { модель.снято.remove(п.id) } else { модель.снято.insert(п.id) }
                })) {
                    HStack {
                        Text(п.название)
                            .font(.system(size: 14))
                            .lineLimit(2)
                        Spacer(minLength: 6)
                        Text(ДокументыБизнеса.деньги(модель.цена(п.цена)) + " ₸")
                            .font(.system(size: 13, weight: .bold))
                            .monospacedDigit()
                    }
                }
                .toggleStyle(ФлажокПрайса())
            }
        }
    }

    // MARK: Действия

    private var действия: some View {
        VStack(spacing: 8) {
            КнопкаБизнеса(подпись: т("pl_pdf"), занято: модель.занято) { модель.pdf() }
            HStack(spacing: 8) {
                КнопкаРаздела(подпись: т("pl_send"), значок: "paperplane") {
                    withAnimation { отправкаОткрыта.toggle() }
                }
                Menu {
                    ForEach([15, 60, 1440], id: \.self) { минут in
                        Button(подписьМинут(минут)) { поделитьсяСсылкой(минут) }
                    }
                } label: {
                    Label(т("pl_share"), systemImage: "link")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.акцент)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.оттенокАкцента,
                                    in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                }
            }
            if отправкаОткрыта {
                HStack(spacing: 8) {
                    TextField(т("pl_bin_ph"), text: $бин)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                    Button(т("send")) {
                        модель.отправить(бин: бин) { текст, удача, безАккаунта in
                            итогОтправки = текст
                            хорошо = удача
                            if безАккаунта { поделитьсяСсылкой(60) }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.акцент)
                    .disabled(модель.занято)
                }
                if let итогОтправки {
                    ЗаметкаБизнеса(итогОтправки, тон: хорошо ? .хорошо : .плохо,
                                   значок: хорошо ? "checkmark.circle" : "exclamationmark.circle")
                }
            }
            КнопкаРаздела(подпись: т("pl_import"), значок: "square.and.arrow.down") { выборФайла = true }
        }
    }

    private func подписьМинут(_ минут: Int) -> String {
        let срок = минут < 60 ? "\(минут) \(т("min_short"))" : "\(минут / 60) \(т("hour_short"))"
        return "\(т("docshare_ttl")): \(срок)"
    }

    private func поделитьсяСсылкой(_ минут: Int) {
        let заголовок = модель.заголовок
        модель.ссылка(минут: минут) { адрес in
            guard let адрес else { return }
            поделиться = СсылкаДляЛиста(адрес: адрес, текст: заголовок)
        }
    }

    private func подпись(_ текст: String) -> some View {
        Text(текст)
            .font(.system(size: 12.5, weight: .bold))
            .foregroundStyle(Theme.текстВторой)
            .padding(.top, 2)
    }
}

/// Флажок выбора позиции (.pl-pick сайта): квадрат слева, текст справа.
private struct ФлажокПрайса: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 18))
                    .foregroundStyle(configuration.isOn ? Theme.акцент : Theme.текстВторой)
                    .accessibilityHidden(true)
                configuration.label
                    .foregroundStyle(Theme.текст)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}

// MARK: - Документы заказа B2B

/// Кнопки документов заказа B2B: счёт, накладная (товары), акт (услуги), договор — свой PDF.
struct КнопкиДокументовЗаказа: View {
    let заказ: ЗаказB2B

    private func т(_ ключ: String) -> String { КабинетПлюсText.т(ключ) }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                кнопка(т("doc_invoice"), значок: "doc.text", часть: nil, вид: "invoice")
                if заказ.вид != "services" {
                    кнопка(т("doc_waybill"), значок: "shippingbox", часть: "goods", вид: "waybill")
                }
                if заказ.вид != "goods" {
                    кнопка(т("doc_act"), значок: "checkmark.seal", часть: "services", вид: "act")
                }
                кнопка(т("doc_contract"), значок: "signature", часть: nil, вид: "contract")
            }
        }
    }

    private func кнопка(_ подпись: String, значок: String, часть: String?, вид: String) -> some View {
        Button {
            var данные = ДанныеДокумента(заказ: заказ.сырое, часть: часть)
            данные.вид = вид
            ОкнаДокументов.показать(ДокументКабинета(заголовок: ДокументыБизнеса.заголовок(данные),
                                                     источник: .разметка(ДокументыБизнеса.разметка(данные))))
        } label: {
            Label(подпись, systemImage: значок)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.акцент)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.оттенокАкцента, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
