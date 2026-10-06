import SwiftUI
import UIKit
import WebKit

/**
 ГАРАНТ-ССЫЛКА ПАРТНЁРА НАТИВНО (dl.php и inc/deal_link.php сайта). Продавец со своего сайта шлёт покупателю
 https://kliko.kz/dl.php?c=<код> — 16 шестнадцатеричных. AASA сайта отдаёт applinks на все пути, кроме admin, api,
 .well-known и courier, так что ссылка приходит универсальной в WebBridge.открытьСнаружи (и из чата — в перейти). Раньше
 её не узнавал ни один разбор (NativeRouter.распознать, БезСайта.ближайший), и перейти показывал окно «Страница недоступна
 в приложении». Теперь её забирает ГарантСсылка.перехватить — сразу после «Войти по QR», раньше прочих разборов.

 Что делает страница сайта и как это здесь:
   · отмечает открытие (партнёр по своему API видит, дошёл ли покупатель) и кладёт цену продавца в inc/offers.php, если
     покупатель вошёл, — это работа сервера, ей нужна только кука сессии. Поэтому запрос — КабинетСайта.открытьСтраницу:
     fetch изнутри страницы под слоем (кука kliko_cab, User-Agent с KlikoApp, настоящие Origin и Referer), обычный GET,
     без подставленных заголовков. Свои проверки денег здесь не повторяются — как и на сайте, их делает касса;
   · кончается перенаправлением 302 на ЧПУ карточки «/<слаг>-<номер>/?buy=1» (&qty=N, если штук больше одной; витрина
     сайта qty пока не читает) — окно закрывается, карточка открывается своим экраном и сразу жмёт кнопку сделки, как
     _mkAfterCard сайта (NativeRouter.распознать, НамерениеОбъявления.купить);
   · или отдаёт свою страницу dl_page: «Ссылка не найдена» (404), «Ссылка отозвана», «Срок ссылки истёк», «Товара больше
     нет», «По этой ссылке уже оплачено» (410, с кнопкой «Вернуться в магазин» — адрес партнёра), «Слишком много
     обращений» (429); техработы и закрытая витрина — общими страницами сайта (503). Заголовок и текст берутся со
     страницы (она запрошена на языке приложения — путь /kz/<язык>/): окно показывает их со щитом гаранта, как
     dl_page, и кнопкой «На главную»;
   · гость, а продавец назначил свою цену, — страница 200 «Войдите, чтобы цена продавца применилась» с кнопкой на
     карточку. Здесь — свой вход (ВходПоверх), после него та же ссылка открывается снова и сервер сам кладёт цену; кнопка
     страницы — карточка без цены, как у сайта.
 Нет связи — «Нет соединения» и «Повторить».
 */
@MainActor
enum ГарантСсылка {
    /// Последний перехваченный код: одна ссылка, пришедшая дважды (холодный старт и continue), не ставит два окна и не
    /// считается у партнёра вторым открытием.
    private static var последний: (код: String, когда: Date)? = nil

    /// Что сказала страница dl.php.
    enum ИтогСсылки: Equatable {
        /// Перенаправила — адрес карточки (или что сервер решит потом): своим экраном.
        case перейти(URL)
        /// Своя страница: нет ссылки, срок вышел, уже оплачено, техработы.
        case страница(СтраницаГарантСсылки)
        /// Гость и цена продавца: сначала вход, потом ссылка снова.
        case вход(СтраницаГарантСсылки)
        /// Не поняли ответ или сервер упал — «Повторить».
        case ошибка(String)
    }

    /**
     Код из адреса гарант-ссылки (/dl.php?c=<код>; без .php и с /kz/<язык> в начале .htaccess сайта открывает ту же
     страницу) — как dl_code_norm сайта: только шестнадцатеричные, в нижнем регистре, ровно 16, иначе пусто (сервер
     ответит своей «Ссылка не найдена»). nil — адрес не гарант-ссылка.
     */
    static func код(из адрес: URL) -> String? {
        let полный = адрес.absoluteURL
        guard let схема = полный.scheme?.lowercased(), схема == "https" || схема == "http",
              let части = URLComponents(url: полный, resolvingAgainstBaseURL: false) else { return nil }
        let путь = части.path.lowercased()
        guard путь.range(of: "^(/[a-z]{2}/[a-z]{2})?/dl(\\.php)?/?$", options: .regularExpression) != nil else {
            return nil
        }
        let сырой = части.queryItems?.first(where: { $0.name == "c" })?.value ?? ""
        let знаки = String(сырой.lowercased().filter { $0.isASCII && $0.isHexDigit })
        return знаки.count == 16 ? знаки : ""
    }

    /// Адрес нашего домена — гарант-ссылка: своё окно; true — забрали.
    static func перехватить(_ адрес: URL) -> Bool {
        guard Config.deepLink(адрес.absoluteURL) != nil, let найден = код(из: адрес) else { return false }
        let сейчас = Date()
        if let было = последний, было.код == найден, сейчас.timeIntervalSince(было.когда) < 3 { return true }
        последний = (найден, сейчас)
        показать(код: найден)
        return true
    }

    /// Окно гарант-ссылки. Холодный старт — ждём, пока уйдёт заставка и появится верхний экран (до 10 с).
    static func показать(код: String) {
        Task { @MainActor in
            for _ in 0..<40 {
                if WebBridge.shared.splashDone && ПоверхВсего.верхний() != nil { break }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            ПоверхВсего.показать(большой: false) { закрыть in
                ОкноГарантСсылки(код: код, закрыть: закрыть)
            }
        }
    }

    /**
     Путь запроса от корня сайта: /kz/<язык>/dl.php?c=<код> — язык тот же, что у Config.страницаСайта и текстов
     приложения, тогда и страница «нет ссылки / срок вышел» приходит на нём (префикс снимает .htaccess сайта, c — на
     месте). Код — только шестнадцатеричные или пусто.
     */
    static func путь(_ код: String) -> String {
        let хвост = "dl.php?c=" + код
        guard let полный = Config.страницаСайта(хвост),
              let части = URLComponents(url: полный, resolvingAgainstBaseURL: true) else { return "/" + хвост }
        let запрос = части.percentEncodedQuery.map { "?" + $0 } ?? ""
        return части.percentEncodedPath + запрос
    }

    /// Разбор ответа страницы: куда вести или что показать.
    static func итог(_ ответ: КабинетСайта.ОтветСтраницы) -> ИтогСсылки {
        if ответ.перенаправлена, let адрес = ответ.адрес, Config.deepLink(адрес) != nil, код(из: адрес) == nil {
            return .перейти(адрес)
        }
        if let страница = разобрать(ответ.текст, код: ответ.код, база: ответ.адрес) {
            /* Страница 200 с кнопкой на нашу карточку — dl_login: гость, а у ссылки цена продавца. */
            if ответ.код == 200, let кнопка = страница.адресКнопки, let цель = цельАдреса(кнопка),
               case .объявление = цель {
                return .вход(страница)
            }
            return .страница(страница)
        }
        switch ответ.код {
        case 404, 410:
            return .страница(СтраницаГарантСсылки(код: ответ.код, заголовок: ГарантСсылкаText.т("gone_t"),
                                                  текст: ГарантСсылкаText.т("gone_s"), кнопка: "", адресКнопки: nil))
        case 429:
            return .страница(СтраницаГарантСсылки(код: ответ.код, заголовок: ГарантСсылкаText.т("busy_t"),
                                                  текст: ГарантСсылкаText.т("busy_s"), кнопка: "", адресКнопки: nil))
        case 500...:
            return .ошибка(ГарантСсылкаText.т("e_srv"))
        default:
            return .ошибка(ГарантСсылкаText.т("e_app"))
        }
    }

    /// Сбой транспорта: нет связи — «Нет соединения», прочее — «Не получилось».
    static func сбой(_ ошибка: Error) -> String {
        (ошибка as? КабинетСайта.Сбой) == .сеть ? ГарантСсылкаText.т("e_net") : ГарантСсылкаText.т("e_app")
    }

    // MARK: Куда вести

    /// Свой экран адреса нашего домена: разбор NativeRouter, а не узнал — запасной разбор ЧПУ карточки.
    static func цельАдреса(_ адрес: URL) -> NativeRouter.Цель? {
        let полный = адрес.absoluteURL
        guard Config.deepLink(полный) != nil else { return nil }
        return NativeRouter.распознать(полный) ?? карточка(полный)
    }

    /**
     Куда привела ссылка (или кнопка её страницы). Наш адрес — своим экраном (карточка по NativeRouter, прочее — тем же
     путём, что у входа снаружи: витрина, кабинет, лента). Адрес партнёра («Вернуться в магазин») — WebBridge.перейти:
     лист Safari внутри приложения, не сайт Kliko.
     */
    static func открыть(_ адрес: URL) {
        let полный = адрес.absoluteURL
        guard Config.deepLink(полный) != nil else {
            WebBridge.shared.перейти(полный)
            return
        }
        if let цель = цельАдреса(полный) {
            WebBridge.shared.открытьЭкран(цель, запасной: полный)
            return
        }
        WebBridge.shared.открытьСнаружи(полный)
    }

    /// Окно уже закрывается — через паузу, как ПоверхВсего.открытьАдрес: экран под листом успевает освободиться.
    static func открытьПотом(_ адрес: URL) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            открыть(адрес)
        }
    }

    /// «На главную» — лента с начала, как главная сайта (WebBridge.перейти для главной).
    static func наГлавную() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            WebBridge.shared.открытьЭкран(.найти(ИскомоеЛенты(текст: "", раздел: "")), запасной: Config.apiBase)
        }
    }

    /**
     Запасной разбор ЧПУ карточки — то же правило, что у .htaccess сайта (слаг, дефис, номер с буквы, от шести знаков,
     с подчёркиванием): номер вида demo_rich NativeRouter не узнаёт. ?buy=1 / ?chat=1 — намерение карточки.
     */
    static func карточка(_ адрес: URL) -> NativeRouter.Цель? {
        guard Config.нативнаяКарточка, Config.deepLink(адрес) != nil,
              let части = URLComponents(url: адрес, resolvingAgainstBaseURL: false) else { return nil }
        let путь = части.path.replacingOccurrences(of: "^/[a-z]{2}/[a-z]{2}(?=/)", with: "",
                                                   options: .regularExpression)
        guard путь.range(of: "^/[a-z0-9-]+-[A-Za-z][A-Za-z0-9_]{5,39}/?$", options: .regularExpression) != nil,
              let хвост = путь.split(separator: "/").last,
              let номер = хвост.split(separator: "-").last else { return nil }
        return .объявление(id: String(номер), намерение: НамерениеОбъявления.из(части.queryItems ?? []))
    }

    // MARK: Страница сайта

    /**
     Страница dl_page (и общие страницы техработ и закрытой витрины): <h1> — заголовок, первый <p> после него — текст,
     <a class="b"> — кнопка. Нет <h1> — заголовок из <title>. Ничего — nil.
     */
    static func разобрать(_ html: String, код: Int, база: URL?) -> СтраницаГарантСсылки? {
        var заголовок = чистый(группы("<h1[^>]*>([\\s\\S]*?)</h1>", в: html)?.first ?? "")
        if заголовок.isEmpty {
            заголовок = чистый(группы("<title[^>]*>([\\s\\S]*?)</title>", в: html)?.first ?? "")
            /* «Витрина закрыта — Kliko.kz» → «Витрина закрыта». */
            if let r = заголовок.range(of: " — ") { заголовок = String(заголовок[..<r.lowerBound]) }
        }
        guard !заголовок.isEmpty else { return nil }
        let текст = чистый(группы("</h1>[\\s\\S]*?<p[^>]*>([\\s\\S]*?)</p>", в: html)?.first
                           ?? группы("<p[^>]*>([\\s\\S]*?)</p>", в: html)?.first ?? "")
        var подпись = ""
        var адресКнопки: URL? = nil
        if let кнопка = группы("<a\\b([^>]*\\bclass\\s*=\\s*[\"']b[\"'][^>]*)>([\\s\\S]*?)</a>", в: html),
           кнопка.count == 2,
           let href = группы("\\bhref\\s*=\\s*[\"']([^\"']*)[\"']", в: кнопка[0])?.first {
            let сырой = РазборСтатьи.декодировать(href).trimmingCharacters(in: .whitespacesAndNewlines)
            if let адрес = URL(string: сырой, relativeTo: база ?? Config.apiBase)?.absoluteURL,
               let схема = адрес.scheme?.lowercased(), схема == "https" || схема == "http" {
                адресКнопки = адрес
                подпись = чистый(кнопка[1])
            }
        }
        return СтраницаГарантСсылки(код: код, заголовок: заголовок, текст: текст,
                                    кнопка: адресКнопки == nil ? "" : подпись, адресКнопки: адресКнопки)
    }

    /// Группы первого совпадения шаблона (без учёта регистра); nil — нет совпадения.
    private static func группы(_ шаблон: String, в тексте: String) -> [String]? {
        guard let выражение = try? NSRegularExpression(pattern: шаблон, options: [.caseInsensitive]) else { return nil }
        let весь = NSRange(тексте.startIndex..<тексте.endIndex, in: тексте)
        guard let совпадение = выражение.firstMatch(in: тексте, options: [], range: весь) else { return nil }
        var итог: [String] = []
        for номер in 1..<max(1, совпадение.numberOfRanges) {
            if let r = Range(совпадение.range(at: номер), in: тексте) {
                итог.append(String(тексте[r]))
            } else {
                итог.append("")
            }
        }
        return итог
    }

    /// Текст без тегов, сущности (&quot; &#039; &amp;) — символами, пробелы — по одному.
    private static func чистый(_ html: String) -> String {
        let безТегов = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return РазборСтатьи.декодировать(безТегов)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Страница dl.php вместо перехода: заголовок, текст и кнопка (a.b) — как напечатал сервер.
struct СтраницаГарантСсылки: Equatable {
    let код: Int
    let заголовок: String
    let текст: String
    /// Подпись кнопки страницы; пусто — кнопки нет.
    let кнопка: String
    /// Куда ведёт кнопка: карточка (dl_login) или магазин партнёра (уже оплачено).
    let адресКнопки: URL?
}

// MARK: - Окно гарант-ссылки

struct ОкноГарантСсылки: View {
    let код: String
    let закрыть: () -> Void

    enum Шаг: Equatable {
        case загрузка
        case страница(СтраницаГарантСсылки)
        case нуженВход(СтраницаГарантСсылки)
        case ошибка(текст: String)
    }

    @State private var шаг: Шаг = .загрузка
    /// Окно смахнули, пока шёл запрос: никуда не ведём.
    @State private var ушло = false

    /// Явный init: у окна есть private-состояние, а открывает его ГарантСсылка.
    init(код: String, закрыть: @escaping () -> Void) {
        self.код = код
        self.закрыть = закрыть
    }

    private func т(_ ключ: String) -> String { ГарантСсылкаText.т(ключ) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                содержимое
            }
            .padding(.horizontal, 24)
            .padding(.top, 26)
            .padding(.bottom, 20)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .task { await загрузить() }
        .onDisappear { ушло = true }
    }

    @ViewBuilder
    private var содержимое: some View {
        switch шаг {
        case .загрузка:
            VStack(spacing: 14) {
                SiteSpinner(размер: 28, толщина: 3)
                    .padding(.top, 30)
                Text(т("loading"))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.текстВторой)
                    .multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .combine)
        case .страница(let страница):
            шапка(значок: "shield", заголовок: страница.заголовок, текст: страница.текст)
            кнопка(т("home"), главная: true) { наГлавную() }
            if let адрес = страница.адресКнопки, !страница.кнопка.isEmpty {
                кнопка(страница.кнопка, главная: false) { перейти(адрес) }
            }
            кнопка(т("close"), главная: false) { закрыть() }
        case .нуженВход(let страница):
            шапка(значок: "shield", заголовок: страница.заголовок, текст: страница.текст)
            кнопка(т("sign_in"), главная: true) { войти() }
            if let адрес = страница.адресКнопки, !страница.кнопка.isEmpty {
                кнопка(страница.кнопка, главная: false) { перейти(адрес) }
            }
            кнопка(т("close"), главная: false) { закрыть() }
        case .ошибка(let текст):
            шапка(значок: "exclamationmark.triangle", заголовок: т("err_t"), текст: текст)
            кнопка(т("retry"), главная: true) { Task { await загрузить() } }
            кнопка(т("close"), главная: false) { закрыть() }
        }
    }

    /// Щит гаранта в мятном круге — как знак страницы dl_page (.ic: круг 64, зелёный контур).
    private func шапка(значок: String, заголовок: String, текст: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: значок)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Theme.зелёный2)
                .frame(width: 64, height: 64)
                .background(Theme.мята, in: Circle())
                .padding(.bottom, 6)
                .accessibilityHidden(true)
            Text(заголовок)
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if !текст.isEmpty {
                Text(текст)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.текстВторой)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func кнопка(_ название: String, главная: Bool, _ действие: @escaping () -> Void) -> some View {
        Button(action: действие) {
            Text(название)
                .font(.system(size: главная ? 16 : 15, weight: главная ? .bold : .semibold))
                .foregroundStyle(главная ? Color.white : Theme.зелёный2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: главная ? 50 : 44)
                .background(главная ? Theme.зелёный : Color.clear,
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Действия

    /// Открыть ссылку на сервере (отметка открытия и цена продавца — там) и решить, что дальше.
    private func загрузить() async {
        шаг = .загрузка
        /* Холодный старт по ссылке: страница под слоем может ещё не родиться — ждём её до 5 с, а не пугаем «Нет
           соединения» (дальше ждёт сам транспорт, пока она не встанет на сайт). */
        var ждали = 0
        while WebBridge.shared.webView == nil && ждали < 20 && !ушло {
            ждали += 1
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        let ответ: КабинетСайта.ОтветСтраницы
        do {
            ответ = try await КабинетСайта.открытьСтраницу(ГарантСсылка.путь(код))
        } catch {
            guard !ушло else { return }
            шаг = .ошибка(текст: ГарантСсылка.сбой(error))
            return
        }
        guard !ушло else { return }
        switch ГарантСсылка.итог(ответ) {
        case .перейти(let адрес):
            закрыть()
            ГарантСсылка.открытьПотом(адрес)
        case .страница(let страница):
            шаг = .страница(страница)
        case .вход(let страница):
            шаг = .нуженВход(страница)
        case .ошибка(let текст):
            шаг = .ошибка(текст: текст)
        }
    }

    private func наГлавную() {
        закрыть()
        ГарантСсылка.наГлавную()
    }

    /// Кнопка страницы: карточка — своим экраном, магазин партнёра — листом Safari внутри приложения.
    private func перейти(_ адрес: URL) {
        закрыть()
        ГарантСсылка.открытьПотом(адрес)
    }

    /// Гость: окно уходит, свой экран входа; вошёл — та же ссылка снова, и сервер сам кладёт цену продавца.
    private func войти() {
        let код = self.код
        закрыть()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            ВходПоверх.показать(готово: {
                Task { @MainActor in
                    /* Экран входа сперва закрывается сам — окно встаёт уже после него. */
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    ГарантСсылка.показать(код: код)
                }
            })
        }
    }
}

// MARK: - Тексты

/// Тексты окна гарант-ссылки на языке телефона (kk/ru/en/ar) — тем же способом, что LinksText. Заголовок и текст
/// страниц «нет ссылки», «срок вышел», «уже оплачено» — не отсюда, а со страницы сервера.
enum ГарантСсылкаText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? тексты["ru"] ?? [:]
        return словарь[ключ] ?? тексты["ru"]?[ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": [
            "loading": "Открываем ссылку продавца…",
            "home": "На главную", "close": "Закрыть", "retry": "Повторить", "sign_in": "Войти",
            "err_t": "Не удалось открыть ссылку",
            "e_net": "Нет соединения. Проверьте интернет и попробуйте ещё раз.",
            "e_app": "Не получилось. Попробуйте ещё раз.",
            "e_srv": "Сервер сейчас не отвечает. Попробуйте чуть позже.",
            "gone_t": "Ссылка больше не действует",
            "gone_s": "Попросите продавца прислать новую.",
            "busy_t": "Слишком много обращений",
            "busy_s": "Откройте ссылку чуть позже."
        ],
        "kk": [
            "loading": "Сатушының сілтемесін ашып жатырмыз…",
            "home": "Басты бетке", "close": "Жабу", "retry": "Қайталау", "sign_in": "Кіру",
            "err_t": "Сілтеме ашылмады",
            "e_net": "Байланыс жоқ. Интернетті тексеріп, қайталап көріңіз.",
            "e_app": "Болмады. Қайталап көріңіз.",
            "e_srv": "Сервер қазір жауап бермей тұр. Сәл кейінірек қайталап көріңіз.",
            "gone_t": "Сілтеме енді жарамсыз",
            "gone_s": "Сатушыдан жаңа сілтеме жіберуін сұраңыз.",
            "busy_t": "Өтініштер тым көп",
            "busy_s": "Сілтемені сәл кейінірек ашыңыз."
        ],
        "en": [
            "loading": "Opening the seller's link…",
            "home": "Go to home", "close": "Close", "retry": "Try again", "sign_in": "Sign in",
            "err_t": "Couldn't open the link",
            "e_net": "No connection. Check the internet and try again.",
            "e_app": "Something went wrong. Please try again.",
            "e_srv": "The server isn't responding right now. Please try a bit later.",
            "gone_t": "This link no longer works",
            "gone_s": "Ask the seller to send a new one.",
            "busy_t": "Too many requests",
            "busy_s": "Open the link a little later."
        ],
        "ar": [
            "loading": "جارٍ فتح رابط البائع…",
            "home": "إلى الصفحة الرئيسية", "close": "إغلاق", "retry": "إعادة المحاولة", "sign_in": "تسجيل الدخول",
            "err_t": "تعذّر فتح الرابط",
            "e_net": "لا يوجد اتصال. تحقّق من الإنترنت وحاول مجددًا.",
            "e_app": "لم ينجح ذلك. حاول مجددًا.",
            "e_srv": "الخادم لا يستجيب الآن. حاول بعد قليل.",
            "gone_t": "هذا الرابط لم يعد صالحًا",
            "gone_s": "اطلب من البائع إرسال رابط جديد.",
            "busy_t": "طلبات كثيرة جدًا",
            "busy_s": "افتح الرابط بعد قليل."
        ]
    ]
}
