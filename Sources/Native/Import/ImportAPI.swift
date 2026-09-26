import Foundation
import WebKit

/**
 ПЕРЕНОС ОБЪЯВЛЕНИЙ ПО ССЫЛКЕ И ЧЕРЕЗ KLIKO AI — ЗАПРОСЫ (этап 50, владелец: «всё приложение нативным»).

 Экран сайта ?go=import / ?go=aiimport (модуль js/cabinet-aiimport.min.js, перенос по ссылке — liGo / liMassGo в
 js/cabinet.min.js, файлы и фото — aiImpFile / aiImpImg / aiImpPhotos в js/cabinet-deals.min.js). Те же вызовы:
   · POST cabinet.php?action=link_import — multipart {csrf, url, own: "1"} → {ok, source, url, title, price, deal,
     realty, category, brand, condition, description, attrs, cpu, gpu, ram, storage, year, city, district, address,
     images[]}. Картинки по images[] телефон качает сам (URLSession, без CORS страницы) и грузит обычной загрузкой фото
     (КабинетСайта.загрузитьФото — uploadImageSmart сайта, с водяным знаком ОбработкаФото);
   · POST cabinet.php?action=ai_import — JSON {csrf, text, image_b64, image_url, photos, first} → {ok, rows[], ai,
     ai_remaining, ai_reason} (_aiParseSingle: фото прайса или разбор кусками по 14 строк);
   · _aiPost сайта — multipart {csrf, payload: JSON} на ai_job_start {photos} → {ok, job, ai_remaining};
     ai_job_text {job, text, last} → {ok, chunks}; ai_job_chunk {job, i} → {ok, rows, ai}; ai_job_photos {job} →
     {ok, phase, at, total, got}; ai_job_get {job} → {ok, job, rows, phase, chunks, done}; ai_job_open {} → {ok, jobs[]};
     ai_job_drop {job}; ai_import_publish {items, job, from} → {ok, added, skipped, skipped_no_title, skipped_banned,
     skipped_cap};
   · перенос списком ссылок публикует тем же ai_import_publish, но JSON {csrf, items} (liMassGo);
   · POST cabinet.php?action=ai_import_extract — multipart {csrf, file} → {ok, text, chars} (Excel, PDF, Word).
 Отказы — как у сайта (_aiJobFail): csrf, auth, gone, ai_off, slots_full (+verify_required), ai_reason need_paid /
 need_verify, shop_required / need_tier. 🔴 Пакеты Kliko AI, слоты и PRO — покупки (Config.цифровыеПокупки): здесь
 не покупаются, только текст сайта и кабинет сайта.

 Всё — только по нажатию: разбор тратит квоту Kliko AI, публикация создаёт черновики в «Неактивных» (на витрину без
 «Опубликовать» они не уходят, imp_draft сайта).
 */
@MainActor
enum ИмпортAPI {
    typealias A = МоиОбъявленияAPI

    /// Файл для multipart: имя поля, имя файла, тип, байты base64.
    struct Файл {
        let поле: String
        let имя: String
        let тип: String
        let base64: String
    }

    enum Сбой: Error {
        case сеть
        case приложение
    }

    // MARK: - Площадки ссылок (LI_HOSTS, liSiteOf)

    /// olx.kz, krisha.kz, kolesa.kz (с www / m), только https. Имя площадки или nil.
    nonisolated static func площадка(_ ссылка: String) -> String? {
        guard let адрес = URL(string: ссылка.trimmingCharacters(in: .whitespacesAndNewlines)),
              адрес.scheme?.lowercased() == "https", var хост = адрес.host?.lowercased() else { return nil }
        for приставка in ["www.", "m."] where хост.hasPrefix(приставка) {
            хост = String(хост.dropFirst(приставка.count))
        }
        switch хост {
        case "olx.kz": return "olx.kz"
        case "krisha.kz": return "krisha.kz"
        case "kolesa.kz": return "kolesa.kz"
        default: return nil
        }
    }

    // MARK: - multipart изнутри страницы сайта

    /// Тело скрипта: u — путь, fields — поля формы, file — {field, name, type, b64} или пусто.
    private static let скриптФормы = """
    try {
      const f = new FormData();
      for (const k of Object.keys(fields || {})) { f.append(k, String(fields[k])); }
      if (file && file.b64) {
        const s = atob(file.b64);
        const a = new Uint8Array(s.length);
        for (let i = 0; i < s.length; i++) { a[i] = s.charCodeAt(i); }
        f.append(file.field, new Blob([a], {type: file.type || 'application/octet-stream'}), file.name || 'file');
      }
      const r = await fetch(u, {method: 'POST', body: f, credentials: 'same-origin', cache: 'no-store'});
      const t = await r.text();
      return JSON.stringify({s: r.status, t: t});
    } catch (e) {
      return JSON.stringify({e: (e && e.name === 'TypeError') ? 'net' : 'js'});
    }
    """

    /// /kz/<язык>/<хвост> — как у страницы кабинета (карта §0.3).
    private static func путь(_ хвост: String) -> String {
        guard let полный = Config.страницаСайта(хвост),
              let части = URLComponents(url: полный, resolvingAgainstBaseURL: true) else { return "/kz/ru/" + хвост }
        let запрос = части.percentEncodedQuery.map { "?" + $0 } ?? ""
        return части.percentEncodedPath + запрос
    }

    /// Страница сайта под слоем, готовая выполнить запрос (как КабинетСайта: ждём до 15 с).
    private static func страница() async throws -> WKWebView {
        guard let web = WebBridge.shared.webView else { throw Сбой.сеть }
        func наСайте() -> Bool {
            guard let адрес = web.url, адрес.scheme?.lowercased() == "https",
                  let хост = адрес.host?.lowercased() else { return false }
            return хост == "kliko.kz" || хост == "www.kliko.kz"
        }
        if наСайте() && !web.isLoading { return web }
        if !наСайте(), !web.isLoading, let главная = Config.страницаСайта("") {
            web.load(URLRequest(url: главная))
        }
        for _ in 0..<60 {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if наСайте() && !web.isLoading { return web }
        }
        throw Сбой.сеть
    }

    /// POST multipart с csrf; на «csrf» — свежий токен и один повтор. nil — ответ не JSON.
    static func форма(_ хвост: String, поля: [String: String], файл: Файл? = nil) async throws -> [String: Any]? {
        var повторили = false
        while true {
            let токен = try await A.токенСейчас()
            if токен.isEmpty { return ["ok": false, "error": "auth"] }
            var все = поля
            все["csrf"] = токен
            var сырьёФайла: [String: String] = [:]
            if let файл {
                сырьёФайла = ["field": файл.поле, "name": файл.имя, "type": файл.тип, "b64": файл.base64]
            }
            let web = try await страница()
            let аргументы: [String: Any] = ["u": путь(хвост), "fields": все, "file": сырьёФайла]
            let сырой: String = try await withCheckedThrowingContinuation { (продолжение: CheckedContinuation<String, Error>) in
                web.callAsyncJavaScript(скриптФормы, arguments: аргументы, in: nil, in: .defaultClient) { итог in
                    switch итог {
                    case .success(let значение):
                        продолжение.resume(returning: (значение as? String) ?? "")
                    case .failure(let ошибка):
                        продолжение.resume(throwing: ошибка)
                    }
                }
            }
            guard let данные = сырой.data(using: .utf8),
                  let объект = (try? JSONSerialization.jsonObject(with: данные)) as? [String: Any] else {
                throw Сбой.приложение
            }
            if let сбой = объект["e"] as? String { throw сбой == "net" ? Сбой.сеть : Сбой.приложение }
            let текст = (объект["t"] as? String) ?? ""
            guard let тело = текст.data(using: .utf8),
                  let j = (try? JSONSerialization.jsonObject(with: тело)) as? [String: Any] else { return nil }
            if A.строка(j["error"]) == "csrf" && !повторили {
                повторили = true
                A.забыть()
                continue
            }
            return j
        }
    }

    /// _aiPost сайта: FormData {csrf, payload: JSON(payload + csrf)}.
    static func задание(_ действие: String, _ полезное: [String: Any]) async throws -> [String: Any] {
        var повторили = false
        while true {
            let токен = try await A.токенСейчас()
            if токен.isEmpty { return ["ok": false, "error": "auth"] }
            var тело = полезное
            тело["csrf"] = токен
            guard let данные = try? JSONSerialization.data(withJSONObject: тело),
                  let строка = String(data: данные, encoding: .utf8) else { throw Сбой.приложение }
            guard let j = try await форма("cabinet.php?action=" + действие, поля: ["payload": строка]) else {
                throw Сбой.приложение
            }
            if A.строка(j["error"]) == "csrf" && !повторили {
                повторили = true
                A.забыть()
                continue
            }
            return j
        }
    }

    // MARK: - Вызовы

    static func перенестиСсылку(_ ссылка: String) async throws -> [String: Any]? {
        try await форма("cabinet.php?action=link_import", поля: ["url": ссылка, "own": "1"])
    }

    /// _aiParseSingle: одна часть текста или фото прайса.
    static func разобратьЧасть(текст: String, картинка64: String, картинкаURL: String, фото: [[String: Any]],
                               первая: Bool) async throws -> [String: Any] {
        try await A.отправить("cabinet.php?action=ai_import",
                              тело: ["text": текст, "image_b64": картинка64, "image_url": картинкаURL, "photos": фото,
                                     "first": первая])
    }

    /// liMassGo: JSON {csrf, items}.
    static func опубликоватьСсылки(_ товары: [[String: Any]]) async throws -> [String: Any] {
        try await A.отправить("cabinet.php?action=ai_import_publish", тело: ["items": товары])
    }

    static func прочитатьФайл(_ файл: Файл) async throws -> [String: Any]? {
        try await форма("cabinet.php?action=ai_import_extract", поля: [:], файл: файл)
    }

    /**
     uploadImageSmart сайта для одного снимка: сжатие и водяной знак (ОбработкаФото), три попытки upload_photo и
     миниатюра. Итог — ответ сервера ({ok, url, thumb} | {prohibited} | {error}).
     */
    static func загрузитьФото(_ данные: Data) async throws -> [String: Any] {
        let готовое = await Task.detached(priority: .userInitiated) { () -> ГотовоеФото? in
            ОбработкаФото.подготовить(данные)
        }.value
        guard let готовое else { return ["ok": false, "error": ""] }
        let основное = ОбработкаФото.dataURL(готовое.картинка)
        let мини = готовое.миниатюра.isEmpty ? "" : ОбработкаФото.dataURL(готовое.миниатюра)
        var повторили = false
        while true {
            let токен = try await A.токенСейчас()
            if токен.isEmpty { return ["ok": false, "error": "auth"] }
            let ответ = try await КабинетСайта.загрузитьФото(картинка: основное, миниатюра: мини, токен: токен).json
            if A.строка(ответ["error"]) == "csrf" && !повторили {
                повторили = true
                A.забыть()
                continue
            }
            return ответ
        }
    }

    /// Картинка с чужой площадки: байты, если это картинка от 1 КБ (как проверка blob сайта).
    nonisolated static func скачать(_ адрес: String) async -> Data? {
        guard let url = URL(string: адрес), let схема = url.scheme?.lowercased(), схема == "https" || схема == "http" else {
            return nil
        }
        var запрос = URLRequest(url: url, timeoutInterval: 20)
        запрос.setValue("image/*", forHTTPHeaderField: "Accept")
        guard let пара = try? await URLSession.shared.data(for: запрос) else { return nil }
        let данные = пара.0
        let ответ = пара.1
        let тип = ((ответ as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        guard данные.count >= 1024, тип.isEmpty || тип.hasPrefix("image/") else { return nil }
        return данные
    }

    /// my_items: черновики с этими названиями среди неактивных — чтобы открыть их правкой (самые новые первыми).
    static func найтиЧерновики(_ названия: [String]) async -> [(id: String, название: String)] {
        guard let j = try? await A.получить("cabinet.php?action=my_items"), A.да(j["ok"]) else { return [] }
        let искомые = Set(названия.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        let сырые: [Any] = (j["items"] as? [Any]) ?? []
        var найдено: [(id: String, название: String, когда: String)] = []
        for запись in сырые {
            guard let т = запись as? [String: Any] else { continue }
            let имя = A.строка(т["title"])
            let статус = A.строка(т["status"])
            guard статус != "approved", искомые.contains(имя.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            else { continue }
            найдено.append((A.строка(т["id"]), имя, A.строка(т["created_at"])))
        }
        найдено.sort { $0.когда > $1.когда }
        var видели: Set<String> = []
        var итог: [(id: String, название: String)] = []
        for н in найдено where !н.id.isEmpty && !видели.contains(н.название.lowercased()) {
            видели.insert(н.название.lowercased())
            итог.append((н.id, н.название))
        }
        return итог
    }
}
