import SwiftUI
import UIKit

/**
 ПЕРЕНОС ОБЪЯВЛЕНИЙ — СОСТОЯНИЕ И ШАГИ (этап 50). Запросы — ИмпортAPI.

 Три способа, как у сайта (_impСпособы): «Ссылка на объявление», «Список ссылок» (до 20, без PRO до 5), «Прайс,
 таблица или фото» (PRO — proHasClient("ai_import")). Шаги: ввод → ход разбора (полоса, подписи сайта, найденные товары
 по одному) → проверка строк (галочка, название, бренд, категория, цена, состояние, характеристики, описание) →
 «Добавить в «Неактивные»» (ai_import_publish пачками по 50) → итог: черновики, «Проверить и опубликовать» — правка
 черновика своим мастером подачи (адрес cabinet.php?edit=<id> → ПодачаОкно.открыть(.правка) через NativeRouter; сам
 мастер здесь не трогаем) и «Открыть «Мои объявления»».

 У сайта одна ссылка сразу заполняет форму подачи. Здесь — тот же link_import, но строка сначала показывается на
 проверку и уходит черновиком, а уже его открывает мастер подачи: так приложение не лезет во внутренности мастера.
 Таблица с понятной шапкой (название, цена, …) читается на телефоне без Kliko AI — как _tblToItems сайта (упрощённо:
 только по названиям столбцов), иначе — задание Kliko AI (ai_job_*), при его сбое — разбор кусками (ai_import).
 */

enum СпособИмпорта: String, CaseIterable, Identifiable {
    case ссылка = "link"
    case список = "many"
    case каталог = "cat"

    var id: String { rawValue }
}

/// Строка на проверку (_aiRows сайта): исходный ответ сервера и правки человека.
struct СтрокаИмпорта: Identifiable, Equatable {
    let id = UUID()
    var выбрана: Bool
    var название: String
    var бренд: String
    var раздел: String
    var цена: String
    var состояние: String
    var описание: String
    var cpu: String
    var gpu: String
    var ram: String
    var storage: String
    var year: String
    var фото: [String]
    /// Ответ сервера целиком — уходит обратно с правками поверх (Object.assign({}, n, …) у aiPublish).
    let исходное: [String: Any]

    static func == (a: СтрокаИмпорта, b: СтрокаИмпорта) -> Bool {
        let тот: Bool = a.id == b.id && a.выбрана == b.выбрана
        let текст: Bool = a.название == b.название && a.бренд == b.бренд && a.раздел == b.раздел
        let прочее: Bool = a.цена == b.цена && a.состояние == b.состояние && a.описание == b.описание
        return тот && текст && прочее && a.фото == b.фото
    }

    init(_ j: [String: Any]) {
        typealias A = МоиОбъявленияAPI
        исходное = j
        название = A.строка(j["title"]).isEmpty ? A.строка(j["name"]) : A.строка(j["title"])
        бренд = A.строка(j["brand"])
        раздел = A.строка(j["category"])
        let ц = A.целое(j["price"])
        цена = ц > 0 ? String(ц) : ""
        состояние = A.строка(j["condition"]) == "new" ? "new" : "used"
        описание = A.строка(j["description"])
        cpu = A.строка(j["cpu"])
        gpu = A.строка(j["gpu"])
        ram = A.строка(j["ram"])
        storage = A.строка(j["storage"])
        year = A.строка(j["year"])
        var картинки: [String] = []
        if let список = j["images"] as? [Any] {
            картинки = список.map { A.строка($0) }.filter { !$0.isEmpty }
        }
        if картинки.isEmpty, !A.строка(j["image"]).isEmpty { картинки = [A.строка(j["image"])] }
        фото = картинки
        /* n=!!title&&price>0 — строка без цены или названия выключена. */
        выбрана = !название.trimmingCharacters(in: .whitespaces).isEmpty && ц > 0
    }

    var ценаЧисло: Int { Int(цена.filter { $0.isASCII && $0.isNumber }) ?? 0 }

    var готова: Bool { !название.trimmingCharacters(in: .whitespaces).isEmpty && ценаЧисло > 0 }

    /// Товар для ai_import_publish: исходное и правки поверх (как aiPublish).
    var товар: [String: Any] {
        var т = исходное
        т["title"] = название.trimmingCharacters(in: .whitespacesAndNewlines)
        т["brand"] = бренд.trimmingCharacters(in: .whitespacesAndNewlines)
        т["category"] = раздел
        т["price"] = ценаЧисло
        т["condition"] = состояние
        т["cpu"] = cpu.trimmingCharacters(in: .whitespaces)
        т["gpu"] = gpu.trimmingCharacters(in: .whitespaces)
        т["ram"] = ram.trimmingCharacters(in: .whitespaces)
        т["storage"] = storage.trimmingCharacters(in: .whitespaces)
        т["year"] = year.trimmingCharacters(in: .whitespaces)
        т["description"] = описание.trimmingCharacters(in: .whitespacesAndNewlines)
        т["images"] = фото
        return т
    }
}

/// Незаконченное задание (ai_job_open → jobs[0]).
struct НезаконченныйРазбор: Equatable {
    let id: String
    let название: String
    let строк: Int
    let процент: Int
}

/// Черновик после публикации — открыть мастером подачи.
struct ЧерновикИмпорта: Identifiable, Equatable {
    let id: String
    let название: String
}

@MainActor
final class ИмпортМодель: ObservableObject {
    typealias A = МоиОбъявленияAPI

    enum Этап: Equatable {
        case ввод
        case идёт
        case проверка
        case готово
    }

    /// Окно-вопрос: лимит объявлений, лимит Kliko AI, «Начать заново?».
    enum Окно: Identifiable, Equatable {
        case лимит(текст: String, верификация: Bool)
        case лимитИИ(верификация: Bool)
        case начатьЗаново(String)

        var id: String {
            switch self {
            case .лимит: return "limit"
            case .лимитИИ: return "ai"
            case .начатьЗаново(let id): return "drop:" + id
            }
        }
    }

    @Published var способ: СпособИмпорта
    @Published var этап: Этап = .ввод
    @Published var окно: Окно? = nil

    // Ввод
    @Published var ссылка = ""
    @Published var моё = false
    @Published var ссылки = ""
    @Published var моиВсе = false
    @Published var текст = ""
    @Published var файлПодпись = ""
    @Published var картинкаПодпись = ""
    @Published var фотоПодпись = ""
    @Published var заметка: String? = nil
    @Published private(set) var грузимВвод = false

    // Ход разбора
    @Published private(set) var прогресс: Double = 0
    @Published private(set) var заголовокХода = ""
    @Published private(set) var подписьХода = ""
    @Published private(set) var найдено: [String] = []
    @Published private(set) var пауза: String? = nil

    // Проверка
    @Published var строки: [СтрокаИмпорта] = []
    @Published private(set) var сИИ = false
    @Published private(set) var осталосьИИ: Int? = nil
    @Published private(set) var изСсылок = false
    @Published private(set) var публикуем: String? = nil
    @Published var ошибкаПубликации: String? = nil

    // Итог
    @Published private(set) var итог = ""
    @Published private(set) var итогПодробно = ""
    @Published private(set) var черновики: [ЧерновикИмпорта] = []

    @Published private(set) var незаконченный: НезаконченныйРазбор? = nil
    @Published private(set) var pro = false
    @Published private(set) var справочники: СправочникиПодачи? = nil

    private var картинкаURL = ""
    private var картинка64 = ""
    private var фотоТоваров: [[String: Any]] = []
    private var задание = ""
    /// Сколько уже ушло в «Неактивные» — «Продолжить добавление» после обрыва начнёт отсюда (from сайта).
    private var опубликовано = 0
    private var добавлено = 0

    init(способ: СпособИмпорта) {
        self.способ = способ
    }

    private func т(_ ключ: String) -> String { ИмпортText.т(ключ) }
    private func т(_ ключ: String, _ з: [String: String]) -> String { ИмпортText.т(ключ, з) }

    // MARK: - Начало

    /// PRO (proHasClient("ai_import")), разделы для выбора категории и незаконченное задание (aiJobCheck).
    func начать() async {
        let бизнес = БизнесМодель.shared
        if бизнес.страница == nil { await бизнес.загрузитьСтраницу() }
        pro = бизнес.страница?.естьФункция("ai_import") ?? false
        if let j = try? await ИмпортAPI.задание("ai_job_open", [:]), A.да(j["ok"]),
           let задания = j["jobs"] as? [Any], let первое = задания.first as? [String: Any] {
            let частей = A.целое(первое["chunks"])
            let готово = A.целое(первое["done"])
            незаконченный = НезаконченныйРазбор(id: A.строка(первое["id"]), название: A.строка(первое["title"]),
                                                строк: A.целое(первое["rows"]),
                                                процент: частей > 0 ? Int((Double(готово) / Double(частей) * 100).rounded()) : 0)
        }
        if справочники == nil, let ответ = try? await КабинетСайта.страницаКабинета() {
            let страница = СтраницаПодачи.разобрать(ответ.html, состояние: ответ.состояние)
            справочники = try? await ЗагрузкаСправочников.загрузить(страница)
        }
    }

    /// Имя раздела по ключу (slug) или как пришло.
    func имяРаздела(_ ключ: String) -> String {
        if ключ.isEmpty || ключ == "other" { return т("cat_other") }
        let имя = справочники?.имя(ключ) ?? ""
        return имя.isEmpty ? ключ : имя
    }

    // MARK: - Одна ссылка (liGo)

    func перенестиСсылку() {
        let адрес = ссылка.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !адрес.isEmpty else { заметка = т("li_need_url"); return }
        guard ИмпортAPI.площадка(адрес) != nil else { заметка = т("li_bad_host"); return }
        guard моё else { заметка = т("li_need_own"); return }
        заметка = nil
        Task { await перенести([адрес]) }
    }

    // MARK: - Список ссылок (liMassGo)

    /// liMassLinks: годные (наших площадок, без повторов) и чужие.
    var разобранныеСсылки: (годные: [String], чужие: Int) {
        var видели: Set<String> = []
        var годные: [String] = []
        var чужие = 0
        let части = ссылки.components(separatedBy: CharacterSet(charactersIn: " \n\t\r,;"))
        for часть in части {
            let с = часть.trimmingCharacters(in: .whitespaces)
            guard !с.isEmpty else { continue }
            if ИмпортAPI.площадка(с) != nil {
                if !видели.contains(с) {
                    видели.insert(с)
                    годные.append(с)
                }
            } else {
                чужие += 1
            }
        }
        return (годные, чужие)
    }

    func перенестиСписок() {
        let годные = разобранныеСсылки.годные
        guard !годные.isEmpty else { заметка = т("lm_need"); return }
        guard моиВсе else { заметка = т("lm_need_own"); return }
        guard годные.count <= 20 else { заметка = т("lm_max"); return }
        if !pro && годные.count > 5 {
            заметка = т("lm_free_max")
            return
        }
        заметка = nil
        Task { await перенести(годные) }
    }

    /// link_import по каждой ссылке, картинки — скачать и загрузить (до 8, у одной — до 10), строки — на проверку.
    private func перенести(_ адреса: [String]) async {
        начатьХод(адреса.count == 1 ? т("lip_t") : т("lm_q"))
        var готовые: [СтрокаИмпорта] = []
        var непрочитано = 0
        var последняяОшибка = ""
        for (номер, адрес) in адреса.enumerated() {
            let доля = Double(номер) / Double(адреса.count)
            let площадка = ИмпортAPI.площадка(адрес) ?? ""
            let подпись = адреса.count == 1 ? т("lip_open")
                : т("lm_item", ["i": String(номер + 1), "n": String(адреса.count), "site": площадка])
            ход(доля + 0.05 / Double(адреса.count), подпись)
            let ответ: [String: Any]?
            do {
                ответ = try await ИмпортAPI.перенестиСсылку(адрес)
            } catch {
                непрочитано += 1
                последняяОшибка = т("no_conn")
                continue
            }
            guard let j = ответ, A.да(j["ok"]) else {
                непрочитано += 1
                let ошибка = A.строка(ответ?["error"])
                if A.нетСессии(ответ ?? [:]) {
                    последняяОшибка = т("e_auth")
                } else {
                    последняяОшибка = ошибка.isEmpty || КабинетСайта.машинныйКод(ошибка) ? т("li_fail") : ошибка
                }
                continue
            }
            if адреса.count == 1 { ход(0.4, т("lip_parse")) }
            let картинки: [String] = ((j["images"] as? [Any]) ?? []).map { A.строка($0) }.filter { !$0.isEmpty }
            let предел = адреса.count == 1 ? 10 : 8
            var загружено: [String] = []
            let всегоФото = min(предел, картинки.count)
            for (i, картинка) in картинки.prefix(предел).enumerated() {
                let внутри = Double(i) / Double(max(1, всегоФото))
                let проФото = т("lip_photo", ["i": String(i + 1), "n": String(всегоФото)])
                let строкаХода = адреса.count == 1 ? проФото : "\(подпись) · \(проФото)"
                ход(доля + (0.4 + 0.55 * внутри) / Double(адреса.count), строкаХода)
                guard let данные = await ИмпортAPI.скачать(картинка),
                      let загрузка = try? await ИмпортAPI.загрузитьФото(данные),
                      A.да(загрузка["ok"]) else { continue }
                let url = A.строка(загрузка["url"])
                if !url.isEmpty { загружено.append(url) }
            }
            готовые.append(строкаСсылки(j, фото: загружено))
            найдено.append(A.строка(j["title"]))
        }
        guard !готовые.isEmpty else {
            этап = .ввод
            заметка = адреса.count == 1 ? (последняяОшибка.isEmpty ? т("li_fail") : последняяОшибка) : т("lm_none")
            return
        }
        ход(1, т("lip_done"))
        строки = готовые
        сИИ = false
        осталосьИИ = nil
        изСсылок = true
        опубликовано = 0
        добавлено = 0
        if непрочитано > 0 { заметка = т("lm_unread", ["n": String(непрочитано)]) }
        try? await Task.sleep(nanoseconds: 400_000_000)
        этап = .проверка
    }

    /// Строка из ответа link_import — поля, как liMassGo кладёт в ai_import_publish.
    private func строкаСсылки(_ j: [String: Any], фото: [String]) -> СтрокаИмпорта {
        let аренда = A.строка(j["deal"]) == "rent"
        let недвижимость = j["realty"] as? [String: Any]
        let срок = A.строка(недвижимость?["term"]) == "daily" ? "day" : "month"
        let цена = A.целое(j["price"])
        let сост = A.строка(j["condition"])
        var товар: [String: Any] = [:]
        товар["title"] = A.строка(j["title"])
        товар["price"] = цена
        товар["brand"] = A.строка(j["brand"])
        товар["category"] = A.строка(j["category"])
        товар["condition"] = сост.isEmpty ? "used" : сост
        товар["description"] = описание(j)
        for ключ in ["cpu", "gpu", "ram", "storage", "year", "city", "district", "address"] {
            товар[ключ] = A.строка(j[ключ])
        }
        товар["images"] = фото
        товар["import_url"] = A.строка(j["url"])
        товар["for_rent"] = аренда
        товар["rent_price_day"] = аренда ? цена : 0
        товар["rent_period"] = срок
        if let недвижимость {
            товар["realty"] = недвижимость
        } else {
            товар["realty"] = NSNull()
        }
        return СтрокаИмпорта(товар)
    }

    /// _liApply: к описанию — характеристики attrs, которых нет в своих полях.
    private func описание(_ j: [String: Any]) -> String {
        var текст = A.строка(j["description"]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let атрибуты = j["attrs"] as? [String: Any], !атрибуты.isEmpty else { return текст }
        let свои: Set<String> = ["Процессор", "Видеокарта", "ОЗУ", "Накопитель", "Год выпуска"]
        var строки: [String] = []
        for ключ in атрибуты.keys.sorted() where !свои.contains(ключ) {
            строки.append(ключ + ": " + A.строка(атрибуты[ключ]))
        }
        guard !строки.isEmpty else { return текст }
        if !текст.isEmpty { текст += "\n\n" }
        return текст + строки.joined(separator: "\n")
    }

    // MARK: - Файл, фото прайса, фото товаров

    func выбранФайл(_ адрес: URL) {
        let доступ = адрес.startAccessingSecurityScopedResource()
        defer { if доступ { адрес.stopAccessingSecurityScopedResource() } }
        guard let данные = try? Data(contentsOf: адрес) else {
            файлПодпись = т("aii_file_fail")
            return
        }
        let имя = адрес.lastPathComponent
        let расширение = адрес.pathExtension.lowercased()
        if ["csv", "tsv", "txt", ""].contains(расширение) {
            let строка = String(data: данные, encoding: .utf8)
                ?? String(data: данные, encoding: .windowsCP1251)
                ?? String(decoding: данные, as: UTF8.self)
            текст = строка
            файлПодпись = имя
            return
        }
        guard данные.count <= 15_728_640 else {
            файлПодпись = т("aii_file_big")
            return
        }
        файлПодпись = т("aii_reading")
        грузимВвод = true
        let тип = расширение == "pdf" ? "application/pdf" : "application/octet-stream"
        let файл = ИмпортAPI.Файл(поле: "file", имя: имя, тип: тип, base64: данные.base64EncodedString())
        Task {
            defer { грузимВвод = false }
            do {
                if let j = try await ИмпортAPI.прочитатьФайл(файл), A.да(j["ok"]) {
                    текст = A.строка(j["text"])
                    let знаков = A.строка(j["chars"])
                    файлПодпись = знаков.isEmpty ? имя : "\(имя) · \(знаков)"
                    заметка = т("aii_file_read")
                } else {
                    файлПодпись = т("aii_file_fail")
                }
            } catch {
                файлПодпись = т("aii_file_fail")
            }
        }
    }

    /// aiImpImg: фото прайса — загрузкой (image_url), не вышло — картинкой в запросе (image_b64).
    func выбранаКартинка(_ данные: Data, имя: String) {
        guard данные.count <= 10_485_760 else {
            картинкаПодпись = т("aii_photo_big")
            return
        }
        картинкаURL = ""
        картинка64 = ""
        картинкаПодпись = т("aii_uploading")
        грузимВвод = true
        Task {
            defer { грузимВвод = false }
            let ответ = try? await ИмпортAPI.загрузитьФото(данные)
            if let ответ, A.да(ответ["prohibited"]) {
                картинкаПодпись = т("aii_prohibited")
                return
            }
            if let ответ, A.да(ответ["ok"]), !A.строка(ответ["url"]).isEmpty {
                картинкаURL = A.строка(ответ["url"])
            } else if let картинка = UIImage(data: данные), let ужатое = ОбработкаФото.ужать(картинка, сторона: 1600),
                      let jpeg = ужатое.jpegData(compressionQuality: 0.8) {
                картинка64 = ОбработкаФото.dataURL(jpeg)
            }
            картинкаПодпись = картинкаURL.isEmpty && картинка64.isEmpty ? т("aii_photo_fail") : имя
        }
    }

    func убратьКартинку() {
        картинкаURL = ""
        картинка64 = ""
        картинкаПодпись = ""
    }

    /// aiImpPhotos: фото товаров по порядку.
    func выбраныФото(_ снимки: [Data]) {
        guard !снимки.isEmpty else { return }
        фотоТоваров = []
        грузимВвод = true
        Task {
            defer { грузимВвод = false }
            for (i, данные) in снимки.enumerated() {
                фотоПодпись = т("aii_uploading_n", ["i": String(i + 1), "n": String(снимки.count)])
                if let ответ = try? await ИмпортAPI.загрузитьФото(данные), A.да(ответ["ok"]),
                   !A.строка(ответ["url"]).isEmpty {
                    фотоТоваров.append(ответ)
                }
            }
            фотоПодпись = т("aii_photos_done", ["n": String(фотоТоваров.count)])
        }
    }

    var естьКартинка: Bool { !картинкаURL.isEmpty || !картинка64.isEmpty }

    // MARK: - Разбор каталога (aiParse)

    func разобрать() {
        let чистый = текст.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !чистый.isEmpty || естьКартинка else {
            заметка = т("need_input")
            return
        }
        заметка = nil
        Task {
            if естьКартинка {
                await разобратьКусками(чистый)
                return
            }
            if let местные = ТаблицаИмпорта.прочитать(чистый), !местные.isEmpty {
                строки = местные.map { СтрокаИмпорта($0) }
                сИИ = false
                осталосьИИ = nil
                изСсылок = false
                опубликовано = 0
                добавлено = 0
                этап = .проверка
                return
            }
            await разобратьЗаданием(чистый)
        }
    }

    /// _aiParseSingle: фото прайса одним запросом или текст кусками по 14 строк.
    private func разобратьКусками(_ чистый: String) async {
        начатьХод(т("prog_t"))
        let части: [String] = естьКартинка ? [""] : кускиТекста(чистый)
        var все: [[String: Any]] = []
        for (i, часть) in части.enumerated() {
            ход(Double(i) / Double(части.count) + 0.04,
                части.count > 1 ? т("prog_part", ["i": String(i + 1), "n": String(части.count), "k": String(все.count)])
                    : т("prog_single"))
            let j: [String: Any]
            do {
                j = try await ИмпортAPI.разобратьЧасть(текст: часть, картинка64: i == 0 ? картинка64 : "",
                                                        картинкаURL: i == 0 ? картинкаURL : "", фото: фотоТоваров,
                                                        первая: i == 0)
            } catch {
                заметка = т("no_conn")
                break
            }
            guard A.да(j["ok"]) else {
                отказ(j)
                return
            }
            сИИ = A.да(j["ai"])
            осталосьИИ = j["ai_remaining"] == nil || j["ai_remaining"] is NSNull ? nil : A.целое(j["ai_remaining"])
            let новые = строкиОтвета(j)
            все += новые
            for н in новые { найдено.append(A.строка(н["title"])) }
        }
        закончитьРазбор(все)
    }

    /// _aiChunkText: больше 14 непустых строк — куски по 14.
    private func кускиТекста(_ текст: String) -> [String] {
        let строки = текст.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard строки.count > 14 else { return [текст] }
        var итог: [String] = []
        var i = 0
        while i < строки.count {
            итог.append(строки[i..<min(i + 14, строки.count)].joined(separator: "\n"))
            i += 14
        }
        return итог
    }

    /// aiParse: ai_job_start → ai_job_text кусками → ai_job_chunk по каждой части → ai_job_photos → готово.
    private func разобратьЗаданием(_ чистый: String) async {
        начатьХод(т("prog_t"))
        let старт: [String: Any]
        do {
            старт = try await ИмпортAPI.задание("ai_job_start", ["photos": фотоТоваров])
        } catch {
            заметка = т("job_fallback")
            await разобратьКусками(чистый)
            return
        }
        guard A.да(старт["ok"]) else {
            отказ(старт)
            return
        }
        задание = A.строка(старт["job"])
        осталосьИИ = старт["ai_remaining"] == nil || старт["ai_remaining"] is NSNull ? nil : A.целое(старт["ai_remaining"])
        let строки = чистый.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        var частей = 0
        var начало = 0
        while начало < строки.count {
            let длина = Self.длинаКуска(строки, начало)
            let конец = min(начало + длина, строки.count)
            ход(Double(конец) / Double(max(1, строки.count)) * 0.06,
                т("prog_upload", ["c": String(конец), "n": String(строки.count)]))
            do {
                let j = try await ИмпортAPI.задание("ai_job_text", ["job": задание,
                                                                     "text": строки[начало..<конец].joined(separator: "\n"),
                                                                     "last": конец >= строки.count ? 1 : 0])
                guard A.да(j["ok"]) else {
                    отказ(j)
                    return
                }
                частей = A.целое(j["chunks"])
            } catch {
                _ = try? await ИмпортAPI.задание("ai_job_drop", ["job": задание])
                задание = ""
                этап = .ввод
                заметка = т("job_upload_fail")
                return
            }
            начало += длина
        }
        await вестиЗадание(частей: частей, готовые: [], было: [])
    }

    /// _aiSliceLen сайта: по 40 строк, пока кусок меньше 80 000 знаков, не больше 200 строк.
    private static func длинаКуска(_ строки: [String], _ начало: Int) -> Int {
        var взято = 0
        var знаков = 0
        while начало + взято < строки.count && взято < 200 {
            let шаг = min(40, строки.count - (начало + взято))
            var размер = 0
            for k in 0..<шаг { размер += строки[начало + взято + k].count + 1 }
            if взято > 0 && знаков + размер > 80_000 { break }
            взято += шаг
            знаков += размер
        }
        return взято > 0 ? взято : min(40, строки.count - начало)
    }

    /// _aiJobDrive + _aiJobPhotos + _aiJobFinish.
    private func вестиЗадание(частей: Int, готовые: [Int], было: [[String: Any]]) async {
        var все = было
        let сделано = Set(готовые)
        var прочитано = сделано.count
        for i in 0..<max(0, частей) where !сделано.contains(i) {
            let процент = Int((Double(прочитано) / Double(max(1, частей)) * 100).rounded())
            ход(min(0.92, Double(процент) / 100 * 0.92), т("prog_read", ["p": String(процент)]))
            do {
                let j = try await ИмпортAPI.задание("ai_job_chunk", ["job": задание, "i": i])
                guard A.да(j["ok"]) else {
                    отказ(j)
                    return
                }
                if A.да(j["ai"]) { сИИ = true }
                let новые = строкиОтвета(j)
                все += новые
                for н in новые { найдено.append(A.строка(н["title"])) }
                прочитано += 1
            } catch {
                остановить(все)
                return
            }
        }
        /* Фото по ссылкам из прайса. */
        for _ in 0..<3000 {
            let j: [String: Any]
            do {
                j = try await ИмпортAPI.задание("ai_job_photos", ["job": задание])
            } catch {
                остановить(все)
                return
            }
            guard A.да(j["ok"]) else {
                отказ(j)
                return
            }
            let всего = A.целое(j["total"])
            let на = A.целое(j["at"])
            let загружено = A.целое(j["got"])
            var подпись = т("prog_photos", ["a": String(на), "t": String(всего)])
            if загружено > 0 { подпись += т("prog_got", ["g": String(загружено)]) }
            ход(0.92 + Double(на) / Double(max(1, всего)) * 0.08, подпись)
            if A.строка(j["phase"]) != "photos" { break }
        }
        /* Фото загрузились на сервере — строки берём заново (с картинками). */
        if let j = try? await ИмпортAPI.задание("ai_job_get", ["job": задание]), A.да(j["ok"]) {
            let свежие = строкиОтвета(j)
            if !свежие.isEmpty { все = свежие }
        }
        закончитьРазбор(все)
    }

    private func строкиОтвета(_ j: [String: Any]) -> [[String: Any]] {
        ((j["rows"] as? [Any]) ?? []).compactMap { $0 as? [String: Any] }
    }

    /// _aiJobPause: распознанное на сервере, «Продолжить с N-й позиции».
    private func остановить(_ все: [[String: Any]]) {
        пауза = т("resume_from", ["n": String(все.count)])
        заголовокХода = т("paused_t")
        подписьХода = т("paused_s")
    }

    func продолжитьПосле() {
        let номер = задание
        пауза = nil
        Task { await продолжить(номер) }
    }

    private func закончитьРазбор(_ все: [[String: Any]]) {
        guard !все.isEmpty else {
            этап = .ввод
            заметка = т("no_rows")
            return
        }
        ход(1, т("prog_done_s"))
        заголовокХода = т("prog_done")
        строки = все.map { СтрокаИмпорта($0) }
        изСсылок = false
        опубликовано = 0
        добавлено = 0
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 520_000_000)
            self.этап = .проверка
        }
    }

    // MARK: - Незаконченный разбор (aiJobResume, aiJobDrop)

    func продолжить(_ номер: String) async {
        начатьХод(т("prog_t"))
        do {
            let j = try await ИмпортAPI.задание("ai_job_get", ["job": номер])
            guard A.да(j["ok"]) else {
                отказ(j)
                return
            }
            задание = A.строка(j["job"]).isEmpty ? номер : A.строка(j["job"])
            незаконченный = nil
            let были = строкиОтвета(j)
            for б in были { найдено.append(A.строка(б["title"])) }
            let готовые: [Int] = ((j["done"] as? [Any]) ?? []).map { A.целое($0) }
            switch A.строка(j["phase"]) {
            case "parse":
                await вестиЗадание(частей: A.целое(j["chunks"]), готовые: готовые, было: были)
            case "photos":
                await вестиЗадание(частей: 0, готовые: [], было: были)
            default:
                закончитьРазбор(были)
            }
        } catch {
            этап = .ввод
            заметка = т("no_conn")
        }
    }

    func спроситьНачатьЗаново() {
        guard let н = незаконченный else { return }
        окно = .начатьЗаново(н.id)
    }

    func начатьЗаново(_ номер: String) {
        незаконченный = nil
        Task { _ = try? await ИмпортAPI.задание("ai_job_drop", ["job": номер]) }
    }

    // MARK: - Отказы (_aiJobFail)

    private func отказ(_ j: [String: Any]) {
        этап = .ввод
        let ошибка = A.строка(j["error"])
        if ошибка == "csrf" { заметка = т("e_csrf"); return }
        if ошибка == "auth" { заметка = т("e_auth"); return }
        if A.да(j["gone"]) {
            задание = ""
            заметка = т("e_gone")
            return
        }
        if A.да(j["ai_off"]) {
            заметка = ошибка.isEmpty || КабинетСайта.машинныйКод(ошибка) ? т("e_ai_off") : ошибка
            return
        }
        if A.да(j["slots_full"]) {
            let текст = ошибка.isEmpty || КабинетСайта.машинныйКод(ошибка) ? т("lim_s") : ошибка
            окно = .лимит(текст: текст, верификация: A.да(j["verify_required"]))
            return
        }
        let причина = A.строка(j["ai_reason"])
        if причина == "need_paid" || причина == "need_verify" {
            окно = .лимитИИ(верификация: причина == "need_verify")
            return
        }
        if A.да(j["shop_required"]) || A.да(j["need_tier"]) {
            заметка = т("pub_pro")
            return
        }
        let текст = ошибка.isEmpty || КабинетСайта.машинныйКод(ошибка) ? т("e_fail") : ошибка
        заметка = т("e_prefix") + текст
    }

    // MARK: - Ход

    private func начатьХод(_ заголовок: String) {
        этап = .идёт
        прогресс = 0
        заголовокХода = заголовок
        подписьХода = ""
        найдено = []
        пауза = nil
    }

    private func ход(_ доля: Double, _ подпись: String) {
        withAnimation(ДвижениеСайта.прогресс) { прогресс = max(прогресс, min(1, доля)) }
        подписьХода = подпись
    }

    // MARK: - Проверка

    var выбранные: [СтрокаИмпорта] { строки.filter { $0.выбрана } }

    var сумма: Int { строки.reduce(0) { $0 + $1.ценаЧисло } }

    var суммаВыбранных: Int { выбранные.reduce(0) { $0 + $1.ценаЧисло } }

    func выбратьВсе(_ да: Bool) {
        for i in строки.indices { строки[i].выбрана = да }
    }

    func убрать(_ id: UUID) {
        строки.removeAll { $0.id == id }
    }

    func заново() {
        строки = []
        этап = .ввод
        заметка = nil
        публикуем = nil
        ошибкаПубликации = nil
        опубликовано = 0
        добавлено = 0
    }

    // MARK: - Публикация (aiPublish / liMassGo)

    func опубликовать() {
        let товары = выбранные.map { $0.товар }
        guard !товары.isEmpty else {
            ошибкаПубликации = т("no_sel")
            return
        }
        guard публикуем == nil else { return }
        ошибкаПубликации = nil
        Task { await опубликовать(товары) }
    }

    private func опубликовать(_ товары: [[String: Any]]) async {
        var пропущено = 0
        var безНазвания = 0
        var запрещено = 0
        var сверх = 0
        var начало = опубликовано
        while начало < товары.count {
            let конец = min(начало + 50, товары.count)
            публикуем = т("rv_adding", ["a": String(конец), "n": String(товары.count)])
            let пачка = Array(товары[начало..<конец])
            let j: [String: Any]
            do {
                if изСсылок {
                    j = try await ИмпортAPI.опубликоватьСсылки(пачка)
                } else {
                    j = try await ИмпортAPI.задание("ai_import_publish", ["items": пачка, "job": задание, "from": начало])
                }
            } catch {
                публикуем = nil
                опубликовано = начало
                ошибкаПубликации = т("pub_net", ["r": String(начало), "n": String(добавлено)])
                return
            }
            guard A.да(j["ok"]) else {
                публикуем = nil
                опубликовано = начало
                if A.да(j["shop_required"]) || A.да(j["need_tier"]) {
                    ошибкаПубликации = т("pub_pro")
                } else if A.да(j["slots_full"]) {
                    let ошибка = A.строка(j["error"])
                    окно = .лимит(текст: ошибка.isEmpty ? т("lim_s") : ошибка, верификация: A.да(j["verify_required"]))
                } else {
                    let ошибка = A.строка(j["error"])
                    ошибкаПубликации = ошибка.isEmpty || КабинетСайта.машинныйКод(ошибка) ? т("pub_fail") : ошибка
                }
                return
            }
            добавлено += A.целое(j["added"])
            пропущено += A.целое(j["skipped"])
            безНазвания += A.целое(j["skipped_no_title"])
            запрещено += A.целое(j["skipped_banned"])
            сверх += A.целое(j["skipped_cap"])
            начало = конец
            опубликовано = конец
        }
        публикуем = nil
        задание = ""
        итог = изСсылок ? т("li_pub_ok", ["n": String(добавлено)]) : т("pub_ok", ["n": String(добавлено)])
        var подробно: [String] = []
        if пропущено > 0 {
            var причины: [String] = []
            if безНазвания > 0 { причины.append(т("sk_title", ["n": String(безНазвания)])) }
            if запрещено > 0 { причины.append(т("sk_banned", ["n": String(запрещено)])) }
            if сверх > 0 { причины.append(т("sk_cap", ["n": String(сверх)])) }
            var строка = т("pub_skipped", ["n": String(пропущено)])
            if !причины.isEmpty { строка += " (" + причины.joined(separator: ", ") + ")" }
            подробно.append(строка)
        }
        подробно.append(т("pub_after"))
        итогПодробно = подробно.joined(separator: "\n")
        этап = .готово
        let названия = товары.map { A.строка($0["title"]) }
        черновики = await ИмпортAPI.найтиЧерновики(Array(названия.prefix(30))).map {
            ЧерновикИмпорта(id: $0.id, название: $0.название)
        }
    }
}

// MARK: - Таблица без Kliko AI (_tblToItems, упрощённо)

enum ТаблицаИмпорта {
    /// _TBL_SYN сайта: синонимы названий столбцов.
    private static let синонимы: [(String, [String])] = [
        ("title", ["title", "название", "наименование", "товар", "name", "product", "модель", "model", "имя",
                   "наименование_позиции"]),
        ("price", ["price_value", "price", "цена", "стоимость", "cost", "сумма", "cena", "stoimost"]),
        ("description", ["description", "описание", "desc", "текст", "подробности", "primechanie"]),
        ("brand", ["brand", "бренд", "производитель", "manufacturer", "vendor", "марка"]),
        ("images", ["images", "image", "фото", "изображение", "изображения", "картинка", "photo", "picture", "img",
                    "photos", "foto"]),
        ("category", ["category", "категория", "раздел", "тип", "type"]),
        ("condition", ["condition", "состояние", "state", "сост", "sostoyanie"]),
        ("cpu", ["cpu", "процессор", "processor", "проц"]),
        ("ram", ["ram", "озу", "память", "memory"]),
        ("storage", ["storage", "накопитель", "диск", "ssd", "hdd"]),
        ("gpu", ["gpu", "видеокарта", "videocard", "graphics"]),
        ("year", ["year", "год"])
    ]
    private static let пропустить: Set<String> = ["id", "ид", "код", "kod", "guid", "uuid", "uid", "sku", "artikul", "артикул"]

    /// Таблица с шапкой, где есть название: строки товаров. nil — не таблица (пусть читает Kliko AI).
    static func прочитать(_ текст: String) -> [[String: Any]]? {
        let строки = текст.replacingOccurrences(of: "\u{FEFF}", with: "")
            .components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard строки.count >= 2 else { return nil }
        guard let разделитель = разделитель(Array(строки.prefix(20))) else { return nil }
        let таблица = строки.map { разбить($0, разделитель) }
        let шапка = таблица[0]
        var столбцы: [String: Int] = [:]
        var заняты: Set<Int> = []
        for точно in [true, false] {
            for (номер, имя) in шапка.enumerated() where !заняты.contains(номер) {
                let норм = нормализовать(имя)
                guard !норм.isEmpty, !пропустить.contains(норм) else { continue }
                for (поле, варианты) in синонимы where столбцы[поле] == nil {
                    let подходит = варианты.contains { точно ? норм == $0 : норм.contains($0) }
                    if подходит {
                        столбцы[поле] = номер
                        заняты.insert(номер)
                        break
                    }
                }
            }
        }
        guard let столбецНазвания = столбцы["title"] else { return nil }
        var итог: [[String: Any]] = []
        for ряд in таблица.dropFirst() {
            func поле(_ имя: String) -> String {
                guard let i = столбцы[имя], i < ряд.count else { return "" }
                return ряд[i].trimmingCharacters(in: .whitespaces)
            }
            guard столбецНазвания < ряд.count else { continue }
            let название = поле("title")
            guard !название.isEmpty else { continue }
            let цена = Int(поле("price").filter { $0.isASCII && $0.isNumber }) ?? 0
            let сост = поле("condition").lowercased()
            let новый = ["new", "новый", "новое", "нов", "новая", "new_with_tag"].contains(сост)
            let картинки = поле("images").components(separatedBy: CharacterSet(charactersIn: " ,;|"))
                .filter { $0.lowercased().hasPrefix("http") }
            итог.append([
                "title": String(название.prefix(120)), "brand": String(поле("brand").prefix(60)),
                "category": поле("category"), "price": цена, "condition": новый ? "new" : "used",
                "cpu": String(поле("cpu").prefix(60)), "gpu": String(поле("gpu").prefix(60)),
                "ram": String(поле("ram").prefix(60)), "storage": String(поле("storage").prefix(40)),
                "year": String(поле("year").prefix(10)), "description": String(поле("description").prefix(1500)),
                "images": Array(картинки.prefix(8))
            ])
        }
        return итог.isEmpty ? nil : итог
    }

    /// _tblDelim: из «, ; таб |» — тот, что встречается в строке чаще всех.
    private static func разделитель(_ строки: [String]) -> Character? {
        var лучший: Character? = nil
        var больше = 0
        for знак in [",", ";", "\t", "|"] as [Character] {
            var n = 0
            for с in строки { n = max(n, с.filter { $0 == знак }.count) }
            if n > больше {
                больше = n
                лучший = знак
            }
        }
        return лучший
    }

    /// Строка CSV с кавычками.
    private static func разбить(_ строка: String, _ разделитель: Character) -> [String] {
        var поля: [String] = []
        var текущее = ""
        var вКавычках = false
        var предыдущая: Character? = nil
        for знак in строка {
            if знак == "\"" {
                if вКавычках && предыдущая == "\"" {
                    текущее.append("\"")
                    предыдущая = nil
                    continue
                }
                вКавычках.toggle()
            } else if знак == разделитель && !вКавычках {
                поля.append(текущее)
                текущее = ""
            } else {
                текущее.append(знак)
            }
            предыдущая = знак
        }
        поля.append(текущее)
        return поля
    }

    /// _tblNorm: строчные, всё кроме букв и цифр — «_».
    private static func нормализовать(_ имя: String) -> String {
        var итог = ""
        var подчёркивание = false
        for знак in имя.lowercased() {
            if знак.isLetter || знак.isNumber {
                итог.append(знак)
                подчёркивание = false
            } else if !подчёркивание && !итог.isEmpty {
                итог.append("_")
                подчёркивание = true
            }
        }
        while итог.hasSuffix("_") { итог.removeLast() }
        return итог
    }
}
