import Foundation
import UIKit

/**
 РАБОТА: МАСТЕР РЕЗЮМЕ И ВАКАНСИИ — ДАННЫЕ И ЗАПРОСЫ (этап 50, владелец: «всё приложение нативным»).

 Мастер сайта jobWizOpen / _jw2* (js/cabinet.min.js, карта кабинета §2.4.27 и §6.7) и документ резюме jrDocHTML
 (js/jobs-resume.min.js). Путь — от корня, без /kz/<язык> (_ULX_BASE + "/api/jobs.php"):
   · GET  /api/jobs.php?action=mine                → {jobs[]} — для правки своей записи (jobsMineEdit берёт поля оттуда);
   · POST /api/jobs.php?action=create | update     — JSON {csrf, kind, title, city, salary_min, (id)} и у резюме
     name, about, relocate, photo, template, skills[{name, level}], experience[{position, company, period, desc}];
     у вакансии company, salary_max, employment, experience_req, description → ok | error need_verify | limit | msg;
   · POST /api/jobs.php?action=ai_resume           — JSON {csrf, role, exp} → {ok, title, about, skills[], msg};
   · фото 3×4 — POST cabinet.php?action=upload_photo (КабинетСайта.загрузитьФото, как у аватара — без водяного знака:
     сайт шлёт файл как есть) → url || thumb.
 «В ТОП» резюме (/api/jobs.php?action=promote — кошелёк сайта) здесь не вызывается никогда: в приложении ТОП резюме —
 только покупка App Store (ВидУслугиApple.топРезюме, за Config.цифровыеПокупки), услугу включает сайт по чеку Apple.
 */

enum ВидРаботы: String {
    case резюме = "resume"
    case вакансия = "vacancy"
}

/// Навык резюме: название и уровень 0–100 (пусто — полоса 85 %, как jrDocHTML).
struct НавыкРезюме: Identifiable, Equatable {
    let id = UUID()
    var название: String
    var уровень: String
}

/// Место работы: должность, компания, период, описание.
struct ОпытРезюме: Identifiable, Equatable {
    let id = UUID()
    var должность: String
    var компания: String
    var период: String
    var описание: String
}

/// Значения мастера (_jw2.vals сайта) — резюме и вакансия вместе, как у сайта.
struct ЗаписьРаботы: Equatable {
    var вид: ВидРаботы = .резюме
    var имя = ""
    var должность = ""
    var компания = ""
    var город = ""
    var фото = ""
    var оСебе = ""
    var описание = ""
    var зарплатаОт = ""
    var зарплатаДо = ""
    var переезд = false
    /// full · part · shift · remote · internship (_JW_EMP).
    var занятость = "full"
    /// «Без опыта» · «1–3 года» · «3–5 лет» · «5+ лет» — уходит по-русски, как у сайта (_JW_EXP).
    var опытНужен = ""
    var шаблон = "classic"
    var навыки: [НавыкРезюме] = []
    var опыт: [ОпытРезюме] = []
    /// Языки и образование мастер не правит — приходят с сервера и показываются в документе.
    var языки: [(String, String)] = []
    var образование: [(String, String)] = []
    var телефон = ""

    static func == (a: ЗаписьРаботы, b: ЗаписьРаботы) -> Bool {
        a.вид == b.вид && a.должность == b.должность && a.имя == b.имя && a.город == b.город
    }

    /// jobsMineEdit: поля записи из /api/jobs.php?action=mine.
    init() {}

    init(_ j: [String: Any]) {
        typealias A = МоиОбъявленияAPI
        вид = A.строка(j["kind"]) == "vacancy" ? .вакансия : .резюме
        имя = A.строка(j["name"])
        должность = A.строка(j["title"])
        компания = A.строка(j["company"])
        город = A.строка(j["city"])
        фото = A.строка(j["photo"])
        оСебе = A.строка(j["about"])
        описание = A.строка(j["description"])
        let от = A.целое(j["salary_min"])
        зарплатаОт = от > 0 ? String(от) : ""
        let до = A.целое(j["salary_max"])
        зарплатаДо = до > 0 ? String(до) : ""
        переезд = A.да(j["relocate"])
        let з = A.строка(j["employment"])
        занятость = з.isEmpty ? "full" : з
        опытНужен = A.строка(j["experience_req"])
        let ш = A.строка(j["template"])
        шаблон = ш.isEmpty ? "classic" : ш
        навыки = ((j["skills"] as? [Any]) ?? []).compactMap { запись -> НавыкРезюме? in
            if let н = запись as? [String: Any] {
                return НавыкРезюме(название: A.строка(н["name"]), уровень: A.строка(н["level"]))
            }
            let имя = A.строка(запись)
            return имя.isEmpty ? nil : НавыкРезюме(название: имя, уровень: "")
        }
        опыт = ((j["experience"] as? [Any]) ?? []).compactMap { запись -> ОпытРезюме? in
            guard let о = запись as? [String: Any] else { return nil }
            return ОпытРезюме(должность: A.строка(о["position"]), компания: A.строка(о["company"]),
                              период: A.строка(о["period"]), описание: A.строка(о["desc"]))
        }
        языки = ((j["languages"] as? [Any]) ?? []).compactMap { запись -> (String, String)? in
            guard let л = запись as? [String: Any] else { return nil }
            return (A.строка(л["name"]), A.строка(л["level"]))
        }
        образование = ((j["education"] as? [Any]) ?? []).compactMap { запись -> (String, String)? in
            guard let о = запись as? [String: Any] else { return nil }
            return (A.строка(о["title"]), A.строка(о["period"]))
        }
        let контакты = (j["contacts"] as? [String: Any]) ?? [:]
        телефон = A.строка(контакты["phone"])
    }

    /// _jw2Save: тело create/update.
    var тело: [String: Any] {
        var т: [String: Any] = [
            "kind": вид.rawValue,
            "title": должность.trimmingCharacters(in: .whitespacesAndNewlines),
            "city": город.trimmingCharacters(in: .whitespacesAndNewlines),
            "salary_min": Int(зарплатаОт.filter { $0.isASCII && $0.isNumber }) ?? 0
        ]
        switch вид {
        case .резюме:
            т["name"] = имя.trimmingCharacters(in: .whitespacesAndNewlines)
            т["about"] = оСебе
            т["relocate"] = переезд
            т["photo"] = фото
            т["template"] = шаблон
            т["skills"] = навыки.map { ["name": $0.название, "level": $0.уровень] }
            т["experience"] = опыт.map {
                ["position": $0.должность, "company": $0.компания, "period": $0.период, "desc": $0.описание]
            }
        case .вакансия:
            т["company"] = компания.trimmingCharacters(in: .whitespacesAndNewlines)
            т["salary_max"] = Int(зарплатаДо.filter { $0.isASCII && $0.isNumber }) ?? 0
            т["employment"] = занятость.isEmpty ? "full" : занятость
            т["experience_req"] = опытНужен
            т["description"] = описание
        }
        return т
    }
}

@MainActor
enum РезюмеAPI {
    typealias A = МоиОбъявленияAPI

    enum Итог {
        case готово
        case нужнаВерификация(String)
        case предел(String)
        case нуженВход
        case ошибка(String)
    }

    private static func т(_ ключ: String) -> String { РезюмеText.т(ключ) }

    /// Своя запись по номеру (jobsMineEdit).
    static func запись(_ номер: String) async -> ЗаписьРаботы? {
        guard let j = try? await A.получить("/api/jobs.php?action=mine", отКорня: true) else { return nil }
        let записи: [Any] = (j["jobs"] as? [Any]) ?? []
        for запись in записи {
            guard let р = запись as? [String: Any], A.строка(р["id"]) == номер else { continue }
            return ЗаписьРаботы(р)
        }
        return nil
    }

    /// _jw2Save.
    static func сохранить(_ запись: ЗаписьРаботы, номер: String?) async -> Итог {
        var тело = запись.тело
        if let номер { тело["id"] = номер }
        let действие = номер == nil ? "create" : "update"
        do {
            let j = try await A.отправить("/api/jobs.php?action=" + действие, тело: тело, отКорня: true)
            if A.да(j["ok"]) {
                /* jobsMineLoad(true) сайта: списки «Работы» в профиле перечитываются, а не ждут потягивания вниз. */
                NotificationCenter.default.post(name: .klikoРаботаСохранена, object: nil)
                return .готово
            }
            if A.нетСессии(j) { return .нуженВход }
            let сообщение = A.строка(j["msg"])
            switch A.строка(j["error"]) {
            case "need_verify": return .нужнаВерификация(сообщение.isEmpty ? т("jw_need_ver") : сообщение)
            /* Предел активных резюме покупкой не поднимается: только текст — без цены, оплаты и сайта (3.1.1). */
            case "limit": return .предел(РасширениеЛимита.текстСервера(сообщение, запасной: т("jw_limit")))
            default: return .ошибка(сообщение.isEmpty ? т("jw_fail") : сообщение)
            }
        } catch {
            return .ошибка(т("no_net"))
        }
    }

    /// Итог _jw2AI: черновик или готовый текст отказа для человека.
    enum ЧерновикИИ {
        /// своимИИ — сервер сказал, что черновик собрал свой ИИ человека (own_ai_run, договор «Свой ИИ»).
        case готово(title: String, about: String, skills: [String], своимИИ: Bool)
        /// Отказ своего ИИ (его готовый текст), msg сервера, «Не удалось» или «Нет соединения».
        case отказ(String)
        /// Квота Kliko AI кончилась (need_paid) — своя фраза; мастер предложит «Больше Kliko AI».
        case лимитИИ(String)
        case нуженВход
    }

    /**
     _jw2AI: черновик от Kliko AI — должность, «о себе», навыки. С действующим «Своим ИИ» тот же запрос идёт через ключ
     человека (договор §4: только сессией кабинета — так и шлём, КабинетСайта с куками, без Bearer).
     */
    static func собрать(роль: String, опыт: String) async -> ЧерновикИИ {
        let j: [String: Any]
        do {
            j = try await A.отправить("/api/jobs.php?action=ai_resume", тело: ["role": роль, "exp": опыт],
                                      отКорня: true)
        } catch КабинетСайта.Сбой.сеть {
            return .отказ(т("no_net"))
        } catch {
            /* Не JSON (страница 500), нет токена страницы — это сбой сервера, а не связи. */
            return .отказ(т("jw_ai_fail"))
        }
        guard A.да(j["ok"]) else {
            if A.нетСессии(j) { return .нуженВход }
            /* «Свой ИИ» (договор §5): error "own_ai", own_ai:"<код>", текст в msg — окно с готовым текстом
               и действиями, а под кнопкой тот же текст, не общее «Не удалось». */
            if let отказ = ОтказСвоегоИИ.из(j) {
                ОкноСвоегоИИ.показатьОтказ(отказ)
                return .отказ(отказ.текст)
            }
            /* Кнопка «Больше Kliko AI» — только по need_paid: что пакет снимает error limit или quota черновика (может
               быть суточной частотой), сервер не обещал (2.3) — там своя фраза без кнопки (отказКвотыИИ). */
            if РасширениеЛимита.квотаИИ(j) { return .лимитИИ(ПодачаText.т("ai_need_paid")) }
            if let своя = отказКвотыИИ(j) { return .отказ(своя) }
            let сообщение = A.строка(j["msg"]).trimmingCharacters(in: .whitespacesAndNewlines)
            return .отказ(сообщение.isEmpty || КабинетСайта.машинныйКод(сообщение) ? т("jw_ai_fail") : сообщение)
        }
        let навыки: [String] = ((j["skills"] as? [Any]) ?? []).map { String(A.строка($0).prefix(50)) }
            .filter { !$0.isEmpty }
        return .готово(title: A.строка(j["title"]), about: A.строка(j["about"]), skills: навыки,
                       своимИИ: ОтветСвоегоИИ.своим(j))
    }

    /**
     Квота и доступ Kliko AI (need_paid, ai_reason, limit, ai_off) — своя фраза, а не msg сервера: сайт в таких ответах
     зовёт купить пакет Kliko AI у себя, а в приложении он продаётся только через App Store (3.1.1, 3.1.3) — кнопку
     «Больше Kliko AI» даёт мастер по .лимитИИ (только need_paid), как в подаче и импорте; limit и quota — та же фраза
     без кнопки. Прочие отказы — nil: их msg показывается как есть.
     */
    private static func отказКвотыИИ(_ j: [String: Any]) -> String? {
        let ошибка = A.строка(j["error"])
        let причина = A.строка(j["ai_reason"])
        if РасширениеЛимита.квотаИИ(j) || ["limit", "quota"].contains(ошибка) { return ПодачаText.т("ai_need_paid") }
        if причина == "need_verify" || ошибка == "need_verify" { return ПодачаText.т("ai_need_verify") }
        if A.да(j["ai_off"]) || ошибка == "ai_off" || !причина.isEmpty { return т("jw_ai_fail") }
        return nil
    }

    /// Фото 3×4: без водяного знака (как файл сайта), 1280 px, JPEG 0,85; миниатюра 420 px. url || thumb.
    static func загрузитьФото(_ данные: Data) async -> String? {
        let готовое = await Task.detached(priority: .userInitiated) { () -> (Data, Data)? in
            guard let картинка = UIImage(data: данные),
                  let большое = ОбработкаФото.ужать(картинка, сторона: 1280)?.jpegData(compressionQuality: 0.85) else {
                return nil
            }
            let мини = ОбработкаФото.ужать(картинка, сторона: 420)?.jpegData(compressionQuality: 0.62) ?? Data()
            return (большое, мини)
        }.value
        guard let готовое else { return nil }
        let основное = ОбработкаФото.dataURL(готовое.0)
        let мини = готовое.1.isEmpty ? "" : ОбработкаФото.dataURL(готовое.1)
        var повторили = false
        while true {
            guard let токен = try? await A.токенСейчас(), !токен.isEmpty else { return nil }
            guard let ответ = try? await КабинетСайта.загрузитьФото(картинка: основное, миниатюра: мини, токен: токен)
            else { return nil }
            let j = ответ.json
            if A.строка(j["error"]) == "csrf" && !повторили {
                повторили = true
                A.забыть()
                continue
            }
            guard A.да(j["ok"]) else { return nil }
            let url = A.строка(j["url"])
            let адрес = url.isEmpty ? A.строка(j["thumb"]) : url
            return адрес.isEmpty ? nil : адрес
        }
    }
}

// MARK: - Оформление документа (JR_TPL)

struct ШаблонРезюме: Identifiable, Equatable {
    enum Раскладка: Equatable {
        case слева
        case справа
        case шапка
        case просто
    }

    let id: String
    let акцент: UInt32
    let акцент2: UInt32
    let serif: Bool
    let раскладка: Раскладка

    var название: String { РезюмеText.т("tpl_" + id) }

    /// JR_TPL сайта: те же восемь, те же краски и раскладки.
    static let все: [ШаблонРезюме] = [
        ШаблонРезюме(id: "classic", акцент: 0x0E5A34, акцент2: 0x0B3A22, serif: false, раскладка: .слева),
        ШаблонРезюме(id: "ocean", акцент: 0x0E4F8A, акцент2: 0x0A2F56, serif: false, раскладка: .слева),
        ШаблонРезюме(id: "berry", акцент: 0x7C2D52, акцент2: 0x4A1730, serif: true, раскладка: .слева),
        ШаблонРезюме(id: "slate", акцент: 0x334155, акцент2: 0x1E293B, serif: false, раскладка: .справа),
        ШаблонРезюме(id: "modern", акцент: 0x0F7A44, акцент2: 0x0B5C33, serif: false, раскладка: .шапка),
        ШаблонРезюме(id: "mono", акцент: 0x111827, акцент2: 0x374151, serif: false, раскладка: .просто),
        ШаблонРезюме(id: "royal", акцент: 0x5B2EA6, акцент2: 0x3B1D70, serif: true, раскладка: .шапка),
        ШаблонРезюме(id: "sand", акцент: 0xA15A12, акцент2: 0x6B3A0C, serif: false, раскладка: .просто)
    ]

    /// jrTplAt: незнакомый — первый.
    static func по(_ id: String) -> ШаблонРезюме {
        все.first(where: { $0.id == id }) ?? все[0]
    }
}

extension Notification.Name {
    /// Мастер сохранил резюме или вакансию (create / update) — «Работа» профиля и блок «Работа» в «Моих объявлениях»
    /// перечитывают /api/jobs.php?action=mine.
    static let klikoРаботаСохранена = Notification.Name("kliko.jobs.saved")
}
