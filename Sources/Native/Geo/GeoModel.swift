import Combine
import Foundation
import WebKit

/**
 ВЫБОР ГОРОДА И РАЙОНА — ЭТАП 32 ПЕРЕХОДА НА SWIFTUI (владелец 25.09.2026: «приложение должно быть почти 100% похоже на
 сайт, только нативное SwiftUI»).

 Город в шапке ленты (этап 25) вёл на ленту сайта: выбор жил только в скрипте страницы. Теперь он свой — лист
 ЛистГорода, как выпадающий список #mk-city-dd сайта: «По всей стране», три города, области с городами, районы Астаны,
 Алматы и Шымкента, поиск и недавние.

 🔴 КАК У САЙТА, А НЕ ПО-СВОЕМУ (js/marketplace.min.js: mkSetCity, mkSetRegion, _mkApiQS в js/marketplace-feed.min.js):
   · город хранится НАЗВАНИЕМ («Астана»), регион — КЛЮЧОМ («abai»), район — КЛЮЧОМ («astana-esil»): так их пишет
     объявление и так их понимает api/listings.php (city=, region=, district=);
   · «По всей стране» — пустой город и пустой регион, в запросе нет ни того ни другого;
   · регион уходит в запрос только без города, район — только с городом, у которого районы есть;
   · выбор хранится только на телефоне (у сайта — localStorage, у нас — UserDefaults): куки у сайта для этого нет, и
     сервер о выборе не знает, пока он не пришёл параметром. Поэтому его получает каждый запрос ленты — сама лента,
     ряды и числа главной, похожие, фоновая проверка сохранённых поисков (ListingsAPI.Запрос.где).
 Три города республиканского значения сайт из быстрых чипов выбирает регионом (region=astana), а автоопределением —
 городом (city=Астана); для Астаны это одни и те же объявления (городов внутри региона нет). Мы берём город: у него есть
 районы, и его понимает страница сайта (ulx_city), а регион после перезагрузки страница забывает.

 СТРАНИЦЫ САЙТА В ПРИЛОЖЕНИИ. Выбор отдаём странице теми же ключами localStorage, что пишет mkSetCity: ulx_city,
 ulx_district и ulx_city_pick="1" (выбрано руками — автоопределение сайта его не перебьёт); следующая загруженная
 страница покажет тот же город. Страница не наша или ещё не загружена — отдаём после её загрузки (WebContainer). Пока
 своего выбора не было, наоборот, перенимаем город, который человек раньше выбрал на сайте, — один раз.

 «Определить автоматически» — запасной путь mkDetectCity сайта: GET api/geo_ip.php → {city, lat, lon}, название
 сверяется со справочником (_mkMatchPlace). Только по нажатию и одним запросом; геопозицию и сторонний геокодер
 (Nominatim сайта) не спрашиваем — город определяется по адресу сети.

 Выбор и недавние — о человеке: при выходе (bye=1) стираются, как стирает свой localStorage сайт.

 Город SEO-страницы каталога (/kupit/<раздел>/<город>/) — не выбор, а отбор одной выдачи (местоСсылки): как у сайта,
 он не пишется ни на диск, ни странице сайта, и ряды главной, «Работа», похожие по-прежнему идут от выбора.

 СПРАВОЧНИК — GeoData.swift, снимок KLK_MK_REFS.MK_GEO и MK_GEO_DISTRICTS из js/mk-refs-ru.js сайта (у сайта это тоже
 не API, а вшитый файл). Названия — русские, как в данных объявлений. Перегенерировать: скачать
 https://kliko.kz/js/mk-refs-ru.js, сохранить скрипт ниже как gen-geo.js и выполнить
 `node gen-geo.js mk-refs-ru.js > Sources/Native/Geo/GeoData.swift`:

     const fs = require("fs");
     const src = fs.readFileSync(process.argv[2], "utf8");
     const fp = (src.match(/fp:([\w-]+)/) || [])[1] || "?";
     const R = new Function(src + ";return KLK_MK_REFS;")();
     const q = s => JSON.stringify(String(s)).replace(/\\u([0-9a-f]{4})/gi, "\\u{$1}");
     const o = ["// СГЕНЕРИРОВАН из js/mk-refs-ru.js сайта (fp:" + fp + ") — не править руками: как перегенерировать, сказано в GeoModel.swift.", "",
       "extension ГеоДанные {", "    /// KLK_MK_REFS.MK_GEO: ключ, название, город ли (type \"city\"), центр области, её города через «|».",
       "    static let регионы: [ГеоРегион] = ["];
     R.MK_GEO.forEach((g, i, a) => o.push("        ГеоРегион(" + q(g.key) + ", " + q(g.name) + ", город: " + (g.type === "city") + ", центр: " + q(g.center || "") +
       ", города: " + q((g.cities || []).join("|")) + ")" + (i < a.length - 1 ? "," : "")));
     o.push("    ]", "    /// KLK_MK_REFS.MK_GEO_DISTRICTS: ключ района, название, город (названием, как в MK_GEO).", "    static let районы: [ГеоРайон] = [");
     const d = []; Object.keys(R.MK_GEO_DISTRICTS).forEach(c => R.MK_GEO_DISTRICTS[c].forEach(r => d.push("        ГеоРайон(" + q(r.k) + ", " + q(r.n) + ", город: " + q(c) + ")")));
     o.push(d.join(",\n"), "    ]", "}", "");
     process.stdout.write(o.join("\n"));
 */

// MARK: - Справочник

/// Регион справочника сайта (MK_GEO): один из трёх городов республиканского значения или область с её городами.
struct ГеоРегион: Identifiable, Hashable, Sendable {
    /// Ключ — region= у api/listings.php: «astana», «abai».
    let ключ: String
    let название: String
    /// type "city" — Астана, Алматы, Шымкент: сами себе город, городов внутри нет.
    let город: Bool
    /// Областной центр («Семей»); у городов — пусто.
    let центр: String
    /// Города области — названиями, как их пишут объявления.
    let города: [String]

    var id: String { ключ }

    /// Города — одной строкой через «|»: так справочник короче и быстрее собирается (GeoData.swift).
    init(_ ключ: String, _ название: String, город: Bool, центр: String, города: String) {
        self.ключ = ключ
        self.название = название
        self.город = город
        self.центр = центр
        self.города = города.split(separator: "|").map(String.init)
    }
}

/// Район города (MK_GEO_DISTRICTS): районы есть только у Астаны, Алматы и Шымкента.
struct ГеоРайон: Identifiable, Hashable, Sendable {
    /// Ключ — district= у api/listings.php: «astana-esil».
    let ключ: String
    let название: String
    /// Город названием — как ключ MK_GEO_DISTRICTS.
    let город: String

    var id: String { ключ }

    init(_ ключ: String, _ название: String, город: String) {
        self.ключ = ключ
        self.название = название
        self.город = город
    }
}

/// Справочник мест. Сами данные — в GeoData.swift (сгенерирован), здесь — как по ним искать.
enum ГеоДанные {
    /// Все города справочника: три города-региона и города областей — как MK_REG_OF сайта.
    static let всеГорода: Set<String> = {
        var имена = Set<String>()
        for регион in регионы {
            if регион.город { имена.insert(регион.название) }
            for город in регион.города { имена.insert(город) }
        }
        return имена
    }()

    /// Астана, Алматы, Шымкент — в порядке справочника.
    static var городаРеспублики: [ГеоРегион] { регионы.filter { $0.город } }
    /// Области — в порядке справочника.
    static var области: [ГеоРегион] { регионы.filter { !$0.город } }

    static func регион(_ ключ: String) -> ГеоРегион? {
        guard !ключ.isEmpty else { return nil }
        return регионы.first { $0.ключ == ключ }
    }

    static func район(_ ключ: String) -> ГеоРайон? {
        guard !ключ.isEmpty else { return nil }
        return районы.first { $0.ключ == ключ }
    }

    static func районыГорода(_ город: String) -> [ГеоРайон] {
        районы.filter { $0.город == город }
    }

    static func естьГород(_ название: String) -> Bool {
        всеГорода.contains(название)
    }

    /// Город-регион (Астана, Алматы, Шымкент) по названию.
    static func регионГорода(_ название: String) -> ГеоРегион? {
        регионы.first { $0.город && $0.название == название }
    }

    /// Первая область, в которой есть город с таким названием (названия бывают у нескольких — «Абай»; сайт тоже берёт
    /// первую, MK_REG_OF).
    static func областьГорода(_ название: String) -> ГеоРегион? {
        регионы.first { !$0.город && $0.города.contains(название) }
    }

    /**
     Название места → выбор: _mkMatchPlace сайта (без учёта регистра, пробелы по краям — прочь). Город — городом, как
     записан в справочнике; область названием — регионом (сайт в таком случае поставил бы названию области city=, и
     лента была бы пустой). Не нашлось — nil.
     */
    static func место(_ название: String) -> ГдеИскать? {
        let искомое = название.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !искомое.isEmpty else { return nil }
        for регион in регионы {
            if регион.название.lowercased() == искомое {
                return регион.город ? ГдеИскать(город: регион.название) : ГдеИскать(регион: регион.ключ)
            }
            if let город = регион.города.first(where: { $0.lowercased() == искомое }) {
                return ГдеИскать(город: город)
            }
        }
        return nil
    }

    /// Район города по названию, как его сверяет сайт перед сортировкой (mkRender): «Есильский район» и «Есильский»
    /// — один район; ключ тоже подходит.
    static func районПоИмени(_ имя: String, города город: String) -> ГеоРайон? {
        let искомое = имя.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !искомое.isEmpty else { return nil }
        let короткое = безСловаРайон(искомое)
        return районыГорода(город).first { р in
            let своё = р.название.lowercased()
            return своё == искомое || безСловаРайон(своё) == короткое || р.ключ == искомое
        }
    }

    private static func безСловаРайон(_ s: String) -> String {
        s.hasSuffix(" район") ? String(s.dropLast(6)) : s
    }
}

// MARK: - Выбор

/// Где искать — mkSt.city, mkSt.region и район сайта. Пустое — вся страна.
struct ГдеИскать: Equatable, Sendable {
    /// Город названием («Астана»); пусто — не город.
    var город = ""
    /// Ключ региона MK_GEO («abai»); только без города.
    var регион = ""
    /// Ключ района MK_GEO_DISTRICTS («astana-esil»); только вместе со своим городом.
    var район = ""

    /// «По всей стране».
    var повсюду: Bool { город.isEmpty && регион.isEmpty }

    /// Параметры api/listings.php — _mkApiQS сайта: city=<название>, без города — region=<ключ>; district=<ключ>.
    var параметры: [URLQueryItem] {
        var поля: [URLQueryItem] = []
        if !город.isEmpty {
            поля.append(URLQueryItem(name: "city", value: город))
            if !район.isEmpty { поля.append(URLQueryItem(name: "district", value: район)) }
        } else if !регион.isEmpty {
            поля.append(URLQueryItem(name: "region", value: регион))
        }
        return поля
    }

    /// Подпись в шапке — mkUpdateCityUI сайта: «Астана · Есильский район», «Семей», «Абайская область»; вся страна — nil.
    var подпись: String? {
        if !город.isEmpty {
            if let р = ГеоДанные.район(район) { return город + " · " + р.название }
            return город
        }
        return ГеоДанные.регион(регион)?.название
    }

    /// Без противоречий: город — из справочника, город-регион — городом, регион — только известный и без города,
    /// район — только своего города. Что не сходится, отбрасываем: лучше вся страна, чем пустая лента по опечатке.
    var проверенное: ГдеИскать {
        var итог = ГдеИскать()
        let имя = город.trimmingCharacters(in: .whitespacesAndNewlines)
        if !имя.isEmpty && ГеоДанные.естьГород(имя) {
            итог.город = имя
            if let р = ГеоДанные.район(район), р.город == имя { итог.район = р.ключ }
        } else if let р = ГеоДанные.регион(регион) {
            if р.город { итог.город = р.название } else { итог.регион = р.ключ }
        }
        return итог
    }

    /// Выбор с телефона. Читается с любой нити (UserDefaults это позволяет) — его берут и фоновые проверки. Рубильник
    /// выключен — вся страна, как до этапа 32.
    static func сохранённое() -> ГдеИскать {
        guard Config.выборГорода else { return ГдеИскать() }
        let х = UserDefaults.standard
        let записано = ГдеИскать(город: х.string(forKey: КлючиГео.город) ?? "",
                                 регион: х.string(forKey: КлючиГео.регион) ?? "",
                                 район: х.string(forKey: КлючиГео.район) ?? "")
        return записано.проверенное
    }
}

/// Недавний выбор — mk_geo_recent сайта ({k:"c"|"r", v}); «d» — наш: районов в листе сайта нет.
struct НедавнееМесто: Hashable, Sendable {
    enum Вид: String, Sendable {
        case город = "c"
        case регион = "r"
        case район = "d"
    }

    let вид: Вид
    /// Город — названием, регион и район — ключом.
    let значение: String

    init(вид: Вид, значение: String) {
        self.вид = вид
        self.значение = значение
    }

    /// Из записи «c:Астана» — так недавние лежат в UserDefaults.
    init?(запись: String) {
        guard let двоеточие = запись.firstIndex(of: ":"),
              let видЗаписи = Вид(rawValue: String(запись[..<двоеточие])) else { return nil }
        let хвост = String(запись[запись.index(after: двоеточие)...])
        guard !хвост.isEmpty else { return nil }
        self.init(вид: видЗаписи, значение: хвост)
    }

    var запись: String { вид.rawValue + ":" + значение }

    /// Что выбрать по нажатию; nil — такого места в справочнике больше нет (сайт такие недавние тоже отбрасывает).
    var где: ГдеИскать? {
        switch вид {
        case .город:
            return ГеоДанные.естьГород(значение) ? ГдеИскать(город: значение) : nil
        case .регион:
            guard let р = ГеоДанные.регион(значение) else { return nil }
            return р.город ? ГдеИскать(город: р.название) : ГдеИскать(регион: р.ключ)
        case .район:
            guard let р = ГеоДанные.район(значение) else { return nil }
            return ГдеИскать(город: р.город, район: р.ключ)
        }
    }

    var название: String { где?.подпись ?? значение }
}

/// Ключи UserDefaults выбора.
private enum КлючиГео {
    static let город = "kliko.geo.city"
    static let регион = "kliko.geo.region"
    static let район = "kliko.geo.district"
    static let недавние = "kliko.geo.recent"
    /// Человек уже выбирал в приложении (или выбор перенят со страницы сайта) — со страницы больше не перенимаем.
    static let выбран = "kliko.geo.picked"
}

/// Выбор города на приложение: шапка ленты, лист выбора и все запросы ленты.
@MainActor
final class ВыборГорода: ObservableObject {
    static let shared = ВыборГорода()

    /// Недавних — три, как у сайта (_mkGeoRecent: slice(0,3)).
    static let предел = 3

    @Published private(set) var где: ГдеИскать
    /// Место SEO-страницы каталога (/kupit/<раздел>/<город>/[<район>/], СсылкиЛенты.местоSEO) — только выдаче ленты,
    /// открытой этой ссылкой: сайт кладёт город страницы в отбор (mkSt.city = MK_SEO.city), а выбор человека (ulx_city)
    /// не пишет. Не на диск и не странице сайта; снимают его выбор в листе, следующий вход в ленту снаружи и выход.
    /// nil — лента ищет по выбору.
    @Published private(set) var местоСсылки: ГдеИскать? = nil
    @Published private(set) var недавние: [НедавнееМесто]
    /// «Определить автоматически» в пути.
    @Published private(set) var определяем = false
    /// Последнее «Определить автоматически» не нашло города — подпись под кнопкой.
    @Published private(set) var неОпределили = false

    /// Выбор ещё не отдан странице сайта. С прошлого запуска — отдаём заново при первой загрузке: страница могла не
    /// успеть его получить, а шапка и страницы сайта должны показывать одно и то же.
    private var ждётСайта: Bool

    private init() {
        где = ГдеИскать.сохранённое()
        недавние = Self.прочитатьНедавние()
        ждётСайта = Config.выборГорода && UserDefaults.standard.bool(forKey: КлючиГео.выбран)
    }

    /// Где ищет лента сейчас: место ссылки каталога, без него — выбор.
    var гдеЛенты: ГдеИскать { местоСсылки ?? где }

    /// Подпись города в шапке: где ищет лента или «По всей стране» (all_kz). Шапка не врёт про место выдачи: с ссылки
    /// каталога — её город, а не выбранный.
    var подпись: String { гдеЛенты.подпись ?? DesignText.т("all_kz") }

    /// Выбор в листе. `место` — что положить в недавние; nil — «По всей стране»: её сайт в недавние не кладёт.
    /// Место ссылки каталога снимается, даже если выбрали тот же город: человек сказал, где ищет.
    func выбрать(_ новое: ГдеИскать, запомнить место: НедавнееМесто?) {
        guard Config.выборГорода else { return }
        if let место { запомнитьНедавнее(место) }
        неОпределили = false
        if местоСсылки != nil { местоСсылки = nil }
        применить(новое.проверенное, наСайт: true)
    }

    /// Место SEO-страницы каталога — ленте (NativeFeedView.применитьСнаружи); nil — снять. Чего нет в справочнике,
    /// не ставим (проверенное), то же, что выбрано, — тоже: лента и так ищет там.
    func поставитьМестоСсылки(_ место: ГдеИскать?) {
        guard Config.выборГорода else { return }
        var итог: ГдеИскать? = nil
        if let годное = место?.проверенное, !годное.повсюду, годное != где { итог = годное }
        if итог != местоСсылки { местоСсылки = итог }
    }

    /// Новый выбор — на диск, в запросы и странице сайта. Тот же — ничего не трогаем: лента и ряды не перегружаются.
    private func применить(_ новое: ГдеИскать, наСайт: Bool) {
        let х = UserDefaults.standard
        х.set(true, forKey: КлючиГео.выбран)
        guard новое != где else { return }
        х.set(новое.город, forKey: КлючиГео.город)
        х.set(новое.регион, forKey: КлючиГео.регион)
        х.set(новое.район, forKey: КлючиГео.район)
        где = новое
        /* Лента на диске (этап 1) — прежнего места: следующий запуск показал бы её под новым городом. */
        ListingsCache.стереть()
        /* Выдача сохранённых поисков (этап 12) теперь из другого места — вся «не виденная». Без новой точки отсчёта
           первая же проверка прислала бы уведомление обо всей первой странице. */
        SavedSearchStore.shared.новаяТочкаОтсчёта()
        if наСайт { отправитьНаСайт() }
    }

    // MARK: - Недавние

    private static func прочитатьНедавние() -> [НедавнееМесто] {
        guard Config.выборГорода else { return [] }
        var итог: [НедавнееМесто] = []
        for запись in UserDefaults.standard.stringArray(forKey: КлючиГео.недавние) ?? [] {
            guard let место = НедавнееМесто(запись: запись), место.где != nil, !итог.contains(место) else { continue }
            итог.append(место)
        }
        return Array(итог.prefix(предел))
    }

    private func запомнитьНедавнее(_ место: НедавнееМесто) {
        var список = недавние.filter { $0 != место }
        список.insert(место, at: 0)
        недавние = Array(список.prefix(Self.предел))
        UserDefaults.standard.set(недавние.map { $0.запись }, forKey: КлючиГео.недавние)
    }

    /// «Очистить» у недавних — mkGeoClear.
    func очиститьНедавние() {
        недавние = []
        UserDefaults.standard.removeObject(forKey: КлючиГео.недавние)
    }

    // MARK: - Определить автоматически

    /// Один запрос к api/geo_ip.php; нашёлся город справочника — выбран, как если бы его нажали. true — выбран.
    func определить() async -> Bool {
        guard Config.выборГорода, !определяем else { return false }
        определяем = true
        неОпределили = false
        let найдено = await ГеоПоIP.место()
        определяем = false
        guard let найдено else {
            неОпределили = true
            return false
        }
        let место = найдено.город.isEmpty ? НедавнееМесто(вид: .регион, значение: найдено.регион)
                                          : НедавнееМесто(вид: .город, значение: найдено.город)
        выбрать(найдено, запомнить: место)
        return true
    }

    // MARK: - Страница сайта

    /**
     Отдать выбор странице — те же ключи, что пишет mkSetCity: ulx_city — город названием (у региона — пусто, как пишет
     mkSetRegion), ulx_district — район НАЗВАНИЕМ: сайт показывает его в шапке как есть («Астана · Есильский район»,
     mkUpdateCityUI), а для сортировки сам сводит название к ключу (mkRender); ulx_city_pick="1" — выбрано руками.
     Только на странице kliko.kz: localStorage чужого сайта (платёжная страница) не трогаем.
     */
    private func отправитьНаСайт() {
        ждётСайта = true
        guard Config.выборГорода, let web = WebBridge.shared.webView else { return }
        let снимок = где
        let имяРайона = ГеоДанные.район(снимок.район)?.название ?? ""
        guard let данные = try? JSONSerialization.data(withJSONObject: [снимок.город, имяРайона]),
              let аргументы = String(data: данные, encoding: .utf8) else { return }
        let js = #"(function(a){try{if(!/(^|\.)kliko\.kz$/.test(location.hostname))return false;var s=localStorage;"#
            + #"s.setItem('ulx_city',a[0]);s.setItem('ulx_district',a[1]);s.setItem('ulx_city_pick','1');return true}"#
            + #"catch(e){return false}})("# + аргументы + ")"
        Task {
            let ответ = try? await web.evaluateJavaScript(js)
            /* Пока шёл ответ, выбрали другое — его отдаст свой вызов. */
            guard (ответ as? Bool) == true, self.где == снимок else { return }
            self.ждётСайта = false
        }
    }

    /// Страница сайта догрузилась (WebContainer, didFinish): не отданный выбор — отдать; своего выбора ещё не было —
    /// перенять тот, что человек сделал на сайте.
    func страницаЗагрузилась() {
        guard Config.выборГорода else { return }
        if ждётСайта {
            отправитьНаСайт()
        } else if !UserDefaults.standard.bool(forKey: КлючиГео.выбран) {
            Task { await self.перенятьССайта() }
        }
    }

    /// Город, выбранный на сайте до этапа 32 (ulx_city при ulx_city_pick="1"), — своим выбором, один раз. Регион сайт
    /// после перезагрузки не помнит, «Весь Казахстан» — это вся страна; их не перенимаем и спросим при следующей загрузке.
    private func перенятьССайта() async {
        guard let web = WebBridge.shared.webView else { return }
        let js = #"(function(){try{if(!/(^|\.)kliko\.kz$/.test(location.hostname))return '';var s=localStorage;"#
            + #"return JSON.stringify({c:s.getItem('ulx_city')||'',d:s.getItem('ulx_district')||'',"#
            + #"p:s.getItem('ulx_city_pick')||''})}catch(e){return ''}})()"#
        guard let строка = try? await web.evaluateJavaScript(js) as? String, !строка.isEmpty,
              let данные = строка.data(using: .utf8),
              let словарь = try? JSONSerialization.jsonObject(with: данные) as? [String: Any] else { return }
        /* Пока спрашивали, человек мог выбрать сам — его выбор главнее. */
        guard !UserDefaults.standard.bool(forKey: КлючиГео.выбран) else { return }
        guard (словарь["p"] as? String) == "1", let город = словарь["c"] as? String,
              var найдено = ГеоДанные.место(город), !найдено.город.isEmpty else { return }
        if let имя = словарь["d"] as? String, let р = ГеоДанные.районПоИмени(имя, города: найдено.город) {
            найдено.район = р.ключ
        }
        применить(найдено.проверенное, наСайт: false)
    }

    // MARK: - Выход

    /// Выход из аккаунта (WebContainer, bye=1): где искал и что выбирал ушедший, следующему не достаётся. Свой
    /// localStorage сайт при выходе чистит сам, поэтому странице ничего не отдаём.
    func стереть() {
        let х = UserDefaults.standard
        for ключ in [КлючиГео.город, КлючиГео.регион, КлючиГео.район, КлючиГео.недавние, КлючиГео.выбран] {
            х.removeObject(forKey: ключ)
        }
        ждётСайта = false
        неОпределили = false
        недавние = []
        местоСсылки = nil
        if где != ГдеИскать() { где = ГдеИскать() }
    }
}

// MARK: - Город по адресу сети

/// GET /api/geo_ip.php → {city, lat, lon} — запасной путь автоопределения сайта (mkDetectCity). Куки не нужны: город
/// определяется по адресу сети, и лишняя сессия на сервере ни к чему.
enum ГеоПоIP {
    private static let сессия: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 10
        c.httpAdditionalHeaders = ["Accept": "application/json"]
        return URLSession(configuration: c)
    }()

    /// Место справочника по городу из ответа; не ответил, не разобрался или города нет в справочнике — nil.
    static func место() async -> ГдеИскать? {
        let адрес = Config.apiBase.appendingPathComponent("api/geo_ip.php")
        let данные: Data
        let ответ: URLResponse
        do { (данные, ответ) = try await сессия.data(from: адрес) } catch { return nil }
        if let http = ответ as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
        guard let объект = try? JSONSerialization.jsonObject(with: данные) as? [String: Any],
              let город = объект["city"] as? String else { return nil }
        return ГеоДанные.место(город)?.проверенное
    }
}

// MARK: - Поиск по справочнику

/// Поиск в листе — как mkCityListHTML сайта: подстрока без учёта регистра, с вариантами запроса mkQueryCands.
enum ГеоПоиск {
    /// Варианты запроса — mkQueryCands: как набрано; то же в русской раскладке (набрали «fcnfyf» — это «астана»,
    /// _mkLayoutEnRu); латиница буквами (_mkTranslit: «almaty» — «алматы»). Пустой запрос — пусто.
    static func варианты(_ запрос: String) -> [String] {
        let строка = запрос.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !строка.isEmpty else { return [] }
        var итог = [строка]
        if строка.contains(where: { раскладка[$0] != nil }) {
            let вРаскладке = String(строка.map { раскладка[$0] ?? $0 })
            if !итог.contains(вРаскладке) { итог.append(вРаскладке) }
        }
        if строка.contains(where: { $0.isASCII && $0.isLetter }) {
            var т = строка
            for пара in сочетания { т = т.replacingOccurrences(of: пара.0, with: пара.1) }
            let транслит = т.map { буквы[$0] ?? String($0) }.joined()
            if !итог.contains(транслит) { итог.append(транслит) }
        }
        return итог
    }

    /// Где в названии первый нашедшийся вариант — _mkGeoFind: символы с какого и по какой; не нашёлся — nil.
    static func найти(_ название: String, _ варианты: [String]) -> Range<Int>? {
        let строчные = название.lowercased()
        for вариант in варианты where !вариант.isEmpty {
            guard let диапазон = строчные.range(of: вариант) else { continue }
            let начало = строчные.distance(from: строчные.startIndex, to: диапазон.lowerBound)
            let длина = строчные.distance(from: диапазон.lowerBound, to: диапазон.upperBound)
            return начало..<(начало + длина)
        }
        return nil
    }

    /// _MK_LAYMAP сайта: латинская раскладка → русская.
    private static let раскладка: [Character: Character] = [
        "q": "й", "w": "ц", "e": "у", "r": "к", "t": "е", "y": "н", "u": "г", "i": "ш", "o": "щ", "p": "з",
        "[": "х", "]": "ъ", "a": "ф", "s": "ы", "d": "в", "f": "а", "g": "п", "h": "р", "j": "о", "k": "л",
        "l": "д", ";": "ж", "'": "э", "z": "я", "x": "ч", "c": "с", "v": "м", "b": "и", "n": "т", "m": "ь",
        ",": "б", ".": "ю"
    ]

    /// _mkTranslit сайта: сначала сочетания, потом буквы.
    private static let сочетания: [(String, String)] = [
        ("shch", "щ"), ("sch", "щ"), ("sh", "ш"), ("ch", "ч"), ("zh", "ж"), ("kh", "х"), ("ts", "ц"),
        ("yo", "ё"), ("yu", "ю"), ("ya", "я"), ("ye", "е")
    ]

    private static let буквы: [Character: String] = [
        "a": "а", "b": "б", "v": "в", "g": "г", "d": "д", "e": "е", "z": "з", "i": "и", "y": "й", "k": "к",
        "l": "л", "m": "м", "n": "н", "o": "о", "p": "п", "r": "р", "s": "с", "t": "т", "u": "у", "f": "ф",
        "h": "х", "c": "к", "j": "ж", "w": "в", "x": "кс", "q": "к"
    ]
}
