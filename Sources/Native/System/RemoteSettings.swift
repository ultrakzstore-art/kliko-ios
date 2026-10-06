import Foundation
import SwiftUI

/**
 НАСТРОЙКИ ПРИЛОЖЕНИЯ С СЕРВЕРА (владелец 29.09.2026: «возможность редактирования с админки iOS настройки»).

 В админке сайта раздел «iOS-приложение» (правка 80 сервера: inc/admin_app_config.php) хранит рубильники и тексты,
 а GET /api/app_config.php отдаёт их: {ok, v, flags:{ключ: bool}, texts:{ключ: строка}}. Приложение читает ответ при
 запуске и при возврате на экран (не чаще раза в 5 минут), с ETag: без изменений сервер отвечает 304 без тела.
 Последний ответ лежит в UserDefaults — с ним приложение стартует до сети.

 ПРАВИЛО: нет ключа в ответе, нет сети, нет кэша — значение сборки (Config.<рубильник>ВСборке). Пока владелец в
 админке ничего не менял, поведение приложения то же, что без сервера.

 ДЕНЬГИ — ТОЛЬКО ВЫКЛЮЧИТЬ. deals_money и wallet_money сервер может лишь погасить (стопКран): выключенное в сборке
 сервер не включит. ПОКУПКИ APP STORE (Config.цифровыеПокупки) СЮДА НЕ ВХОДЯТ И НЕ ДОЛЖНЫ: встроенные покупки
 включаются только сборкой, прошедшей проверку App Review (правила 2.3.1, 3.1.1).

 Ключи — те же, что в белом списке сервера (inc/app_remote_config.php): чужие ключи отбрасываются.

 ПЛАТЁЖНАЯ ОРГАНИЗАЦИЯ (правка 103 сервера, владелец 06.10.2026: «написано Freedom Pay, а эквайер выбирается в
 админке»). Ответ несёт psp {id, title, org:{ru,kz,en,ar}, site} — acq_org_provider() сайта, тот же эквайер, что
 в подвале и «Условиях оплаты». Последнее значение лежит отдельно (ключПлатёжной) и ответом без psp не стирается.
 Не было ни разу — тексты пишут «платёжная организация» без названия (ПлатёжнаяОрганизация.текущая == nil).
 */
enum НастройкиСервера {
    /// Рубильники, которые читает приложение. banner_on — показ полосы над лентой; img_resize — лёгкие фото (img.php).
    static let ключиФлагов: Set<String> = [
        "checks_rk", "ai_recognize", "native_session", "listing_chat", "chat_send", "listing_map",
        "compare", "review_prompt", "whats_new", "deals_money", "wallet_money", "banner_on", "img_resize"
    ]
    /// Тексты: баннер на четырёх языках, минимальная версия, ссылка на App Store; force_lag и force_grace_hours —
    /// числа для принудительного обновления (ПринудительноеОбновление, ForcedUpdate.swift): порог отставания от App Store
    /// в выпусках (0 — выключено) и срок предупреждения в часах. Не прислал сервер — 3 и 72.
    static let ключиТекстов: Set<String> = [
        "banner_ru", "banner_kk", "banner_en", "banner_ar", "min_version", "app_store_url",
        "force_lag", "force_grace_hours"
    ]
    /// Ключи, которые сервер может прислать числом, а не строкой.
    private static let ключиЧисел: Set<String> = ["force_lag", "force_grace_hours"]
    /// Ссылка на приложение в App Store, если сервер свою не дал (та же, что у студии роликов).
    static let ссылкаAppStoreПоУмолчанию = "https://apps.apple.com/kz/app/kliko-kz/id6805824484"

    private static let ключКэша = "kliko.remoteSettings.json"
    private static let ключМетки = "kliko.remoteSettings.etag"
    private static let ключПлатёжной = "kliko.remoteSettings.psp"

    /// Разобранный ответ сервера.
    private struct Снимок {
        var флаги: [String: Bool] = [:]
        var тексты: [String: String] = [:]
        var платёжная: ПлатёжнаяОрганизация? = nil
    }

    private static let замок = NSLock()
    /// Текущие значения: с запуска — из кэша, потом — из свежего ответа. Читаются и пишутся только под замком.
    private static var текущий: Снимок = снимокИзКэша()
    /// Последняя полученная платёжная организация (из своего ключа UserDefaults, потом из свежего ответа).
    private static var платёжная: ПлатёжнаяОрганизация? = платёжнаяИзКэша()

    // MARK: - Разрешение значений

    /// Рубильник «вкл/выкл»: сервер задал — его значение, нет — сборки.
    static func вклВыкл(_ ключ: String, сборка: Bool) -> Bool {
        флаг(ключ) ?? сборка
    }

    /// Стоп-кран: сервер может только выключить. Выключено в сборке — выключено всегда.
    static func стопКран(_ ключ: String, сборка: Bool) -> Bool {
        guard сборка else { return false }
        return флаг(ключ) ?? true
    }

    /// Значение рубильника от сервера или nil — сервер его не задавал.
    static func флаг(_ ключ: String) -> Bool? {
        замок.lock()
        defer { замок.unlock() }
        return текущий.флаги[ключ]
    }

    /// Непустой текст от сервера или nil.
    static func текст(_ ключ: String) -> String? {
        замок.lock()
        defer { замок.unlock() }
        guard let т = текущий.тексты[ключ], !т.isEmpty else { return nil }
        return т
    }

    /// Платёжная организация от сервера (последняя полученная) или nil — сервер её ещё ни разу не назвал.
    static func платёжнаяОрганизация() -> ПлатёжнаяОрганизация? {
        замок.lock()
        defer { замок.unlock() }
        return платёжная
    }

    /// Текст баннера на языке телефона (kk/ru/en/ar); на этом языке пусто — русский.
    static func текстБаннера() -> String? {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let код: String
        switch язык {
        case "kk", "en", "ar": код = язык
        default: код = "ru"
        }
        return текст("banner_" + код) ?? текст("banner_ru")
    }

    /// Ссылка «Обновить»: только apps.apple.com / itunes.apple.com, иначе — ссылка по умолчанию.
    static func ссылкаAppStore() -> URL {
        let запасная = URL(string: ссылкаAppStoreПоУмолчанию)!
        guard let т = текст("app_store_url"),
              т.hasPrefix("https://apps.apple.com/") || т.hasPrefix("https://itunes.apple.com/"),
              let u = URL(string: т) else { return запасная }
        return u
    }

    /// Целое неотрицательное число от сервера (force_lag, force_grace_hours) или nil — не прислал или прислал не число.
    static func целоеЧисло(_ ключ: String) -> Int? {
        guard let т = текст(ключ), let n = Int(т), n >= 0 else { return nil }
        return n
    }

    /// Версия этой сборки ниже min_version сервера.
    static func версияУстарела() -> Bool {
        guard let нужна = текст("min_version") else { return false }
        let своя = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
        return версия(своя, нижеЧем: нужна)
    }

    /// «1.9» ниже «1.12»: сравнение по числам через точку, недостающие — нули.
    static func версия(_ своя: String, нижеЧем нужна: String) -> Bool {
        let а = своя.split(separator: ".").map { Int($0) ?? 0 }
        let б = нужна.split(separator: ".").map { Int($0) ?? 0 }
        let длина = max(а.count, б.count)
        for i in 0..<длина {
            let x = i < а.count ? а[i] : 0
            let y = i < б.count ? б[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    // MARK: - Загрузка

    /// Отдельная сессия без кук и без кэша URLSession: ответ публичный, ETag ведём сами.
    private static let сессия: URLSession = {
        let к = URLSessionConfiguration.ephemeral
        к.urlCache = nil
        к.requestCachePolicy = .reloadIgnoringLocalCacheData
        к.timeoutIntervalForRequest = 10
        return URLSession(configuration: к)
    }()

    /// GET /api/app_config.php. true — пришли новые значения (уже применены и сохранены); 304, ошибка, нет сети — false,
    /// и остаются прежние.
    static func загрузить() async -> Bool {
        guard let адрес = Config.url("/api/app_config.php") else { return false }
        var запрос = URLRequest(url: адрес, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        запрос.setValue("application/json", forHTTPHeaderField: "Accept")
        let хранилище = UserDefaults.standard
        if хранилище.data(forKey: ключКэша) != nil, let метка = хранилище.string(forKey: ключМетки) {
            запрос.setValue(метка, forHTTPHeaderField: "If-None-Match")
        }
        guard let пара = try? await сессия.data(for: запрос),
              let http = пара.1 as? HTTPURLResponse,
              http.statusCode == 200,
              let снимок = разобрать(пара.0) else { return false }
        хранилище.set(пара.0, forKey: ключКэша)
        if let метка = http.value(forHTTPHeaderField: "ETag"), !метка.isEmpty {
            хранилище.set(метка, forKey: ключМетки)
        } else {
            хранилище.removeObject(forKey: ключМетки)
        }
        if let объект = (try? JSONSerialization.jsonObject(with: пара.0)) as? [String: Any],
           снимок.платёжная != nil, let псп = объект["psp"],
           let сырые = try? JSONSerialization.data(withJSONObject: псп) {
            хранилище.set(сырые, forKey: ключПлатёжной)
        }
        поставить(снимок)
        return true
    }

    private static func поставить(_ снимок: Снимок) {
        замок.lock()
        текущий = снимок
        if let п = снимок.платёжная { платёжная = п }
        замок.unlock()
    }

    private static func платёжнаяИзКэша() -> ПлатёжнаяОрганизация? {
        if let данные = UserDefaults.standard.data(forKey: ключПлатёжной),
           let объект = try? JSONSerialization.jsonObject(with: данные),
           let п = ПлатёжнаяОрганизация.разобрать(объект) {
            return п
        }
        return снимокИзКэша().платёжная
    }

    private static func снимокИзКэша() -> Снимок {
        guard let данные = UserDefaults.standard.data(forKey: ключКэша) else { return Снимок() }
        return разобрать(данные) ?? Снимок()
    }

    /// Только ok: true и только ключи из белых списков; тексты — обрезанные, не длиннее 300 знаков.
    private static func разобрать(_ данные: Data) -> Снимок? {
        guard let объект = try? JSONSerialization.jsonObject(with: данные) as? [String: Any],
              (объект["ok"] as? Bool) == true else { return nil }
        var снимок = Снимок()
        if let флаги = объект["flags"] as? [String: Any] {
            for (ключ, значение) in флаги where ключиФлагов.contains(ключ) {
                if let b = значение as? Bool { снимок.флаги[ключ] = b }
            }
        }
        if let тексты = объект["texts"] as? [String: Any] {
            for (ключ, значение) in тексты where ключиТекстов.contains(ключ) {
                var строка = значение as? String
                if строка == nil, ключиЧисел.contains(ключ), let n = значение as? NSNumber { строка = n.stringValue }
                guard let s = строка else { continue }
                let чистый = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !чистый.isEmpty { снимок.тексты[ключ] = String(чистый.prefix(300)) }
            }
        }
        снимок.платёжная = ПлатёжнаяОрганизация.разобрать(объект["psp"])
        return снимок
    }
}

/// Платёжная организация сайта (psp ответа app_config, правка 103): марка, юридическое имя на ru/kz/en/ar, сайт.
struct ПлатёжнаяОрганизация: Equatable {
    let марка: String
    /// Ключи — языки сайта: ru, kz, en, ar.
    let имена: [String: String]
    /// Домен без схемы: tiptoppay.kz.
    let сайт: String

    /// Последняя полученная от сервера или nil — тогда в текстах без названия.
    static var текущая: ПлатёжнаяОрганизация? { НастройкиСервера.платёжнаяОрганизация() }

    /// Юридическое имя на языке приложения (kk → kz сайта), нет на нём — русское, нет и его — марка.
    func имя(язык: String) -> String {
        let код = язык == "kk" ? "kz" : язык
        return имена[код] ?? имена["ru"] ?? марка
    }

    /// https://<site> или nil, если сайта нет.
    var ссылка: URL? {
        сайт.isEmpty ? nil : URL(string: "https://" + сайт)
    }

    /// Имя для Markdown-ссылки: без квадратных скобок, ломающих разметку.
    func имяДляСсылки(язык: String) -> String {
        имя(язык: язык).replacingOccurrences(of: "[", with: "(").replacingOccurrences(of: "]", with: ")")
    }

    /// Разбор psp; имя чистится и обрезается, сайт — только домен из латиницы, цифр, точек и дефисов.
    static func разобрать(_ значение: Any?) -> ПлатёжнаяОрганизация? {
        guard let d = значение as? [String: Any] else { return nil }
        func чистый(_ x: Any?, _ предел: Int) -> String {
            let s = ((x as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return String(s.prefix(предел))
        }
        let марка = чистый(d["title"], 60)
        var имена: [String: String] = [:]
        if let орг = d["org"] as? [String: Any] {
            for код in ["ru", "kz", "en", "ar"] {
                let v = чистый(орг[код], 120)
                if !v.isEmpty { имена[код] = v }
            }
        }
        if марка.isEmpty && имена.isEmpty { return nil }
        var сайт = чистый(d["site"], 80).lowercased()
        let допустимые = Set("abcdefghijklmnopqrstuvwxyz0123456789.-")
        if сайт.isEmpty || !сайт.contains(".") || !сайт.allSatisfy({ допустимые.contains($0) }) || сайт.hasPrefix(".") {
            сайт = ""
        }
        return ПлатёжнаяОрганизация(марка: марка, имена: имена, сайт: сайт)
    }
}

/// Состояние для экранов: баннер над лентой и окно «Обновите приложение». Загрузку зовёт СлойНастроекСервера.
@MainActor
final class НастройкиСервераМодель: ObservableObject {
    static let shared = НастройкиСервераМодель()

    /// Текст полосы над лентой или nil (выключена, пусто, человек закрыл этот текст).
    @Published private(set) var баннер: String? = nil
    /// Версия ниже минимальной (или App Store ушёл вперёд на 1–2 выпуска) и сегодня ещё не спрашивали.
    @Published private(set) var просимОбновить = false
    @Published private(set) var ссылкаAppStore: URL = НастройкиСервера.ссылкаAppStore()

    private let ключЗакрытогоБаннера = "kliko.remoteSettings.bannerClosed"
    private let ключВопросаОбОбновлении = "kliko.remoteSettings.updateAsked"
    /// Когда последний раз ходили на сервер (удачно или нет) — не чаще раза в 5 минут.
    private var последняяПопытка: Date? = nil
    private var идёт = false

    private init() {
        применить()
    }

    /// сразу — при запуске; иначе (возврат на экран) — не чаще раза в 5 минут.
    func обновить(сразу: Bool) async {
        if идёт { return }
        if !сразу, let была = последняяПопытка, Date().timeIntervalSince(была) < 300 { return }
        идёт = true
        последняяПопытка = Date()
        let новые = await НастройкиСервера.загрузить()
        идёт = false
        if новые { применить() }
    }

    /// «×» на полосе: этот текст больше не показываем; новый текст покажется снова.
    func закрытьБаннер() {
        if let т = баннер { UserDefaults.standard.set(т, forKey: ключЗакрытогоБаннера) }
        баннер = nil
    }

    /// Окно показали — следующее не раньше чем через сутки.
    func окноОбновленияПоказано() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: ключВопросаОбОбновлении)
        просимОбновить = false
    }

    /// Пересчитать окно «Обновите приложение» — после свежего ответа App Store (ПринудительноеОбновление).
    func пересчитатьОкноОбновления() {
        применить()
    }

    private func применить() {
        let включён = НастройкиСервера.флаг("banner_on") ?? false
        let текст = включён ? НастройкиСервера.текстБаннера() : nil
        let закрытый = UserDefaults.standard.string(forKey: ключЗакрытогоБаннера)
        if let т = текст, т != закрытый { баннер = т } else { баннер = nil }
        ссылкаAppStore = НастройкиСервера.ссылкаAppStore()
        let спрашивали = UserDefaults.standard.double(forKey: ключВопросаОбОбновлении)
        let давно = Date().timeIntervalSince1970 - спрашивали > 24 * 3600
        let отстали = НастройкиСервера.версияУстарела() || ВерсияВМагазине.мягкоеОтставание()
        просимОбновить = давно && отстали
    }
}

/// Слой на вкладках (NativeTabsView): загрузка при запуске и возврате, полоса над лентой, окно «Обновите приложение».
struct СлойНастроекСервера: ViewModifier {
    @ObservedObject private var настройки = НастройкиСервераМодель.shared
    @Environment(\.scenePhase) private var фаза
    @State private var окноОбновления = false
    /// Лента выбрана и видна — полоса и окно только тогда.
    let лентаНаЭкране: Bool

    init(лентаНаЭкране: Bool) {
        self.лентаНаЭкране = лентаНаЭкране
    }

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if лентаНаЭкране, let текст = настройки.баннер {
                    БаннерНастроекСервера(текст: текст) { настройки.закрытьБаннер() }
                }
            }
            .sheet(isPresented: $окноОбновления) {
                ОкноОбновленияПриложения(ссылка: настройки.ссылкаAppStore) { окноОбновления = false }
            }
            .task {
                await настройки.обновить(сразу: true)
                /* min_version из кэша прошлого запуска: просимОбновить уже true с init, и onChange не срабатывает
                   (ответ 304 его не меняет) — окно показывалось бы только после смены вкладки. */
                проверитьОкно()
            }
            .onChange(of: фаза) { _, стала in
                guard стала == .active else { return }
                Task { await настройки.обновить(сразу: false) }
            }
            .onChange(of: настройки.просимОбновить) { _, _ in проверитьОкно() }
            .onChange(of: лентаНаЭкране) { _, _ in проверитьОкно() }
    }

    private func проверитьОкно() {
        guard лентаНаЭкране, настройки.просимОбновить, !окноОбновления else { return }
        // Предупреждение или запрет устаревшей версии (ForcedUpdate.swift) — мягкое окно поверх них не нужно.
        guard ПринудительноеОбновление.shared.показ == .нет else { return }
        окноОбновления = true
        настройки.окноОбновленияПоказано()
    }
}

/// Жёлтая полоса над лентой: текст из админки и «×».
private struct БаннерНастроекСервера: View {
    let текст: String
    let закрыть: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(red: 0.72, green: 0.42, blue: 0.0))
                .padding(.top, 1)
            Text(текст)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(Color(red: 0.36, green: 0.22, blue: 0.0))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: закрыть) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(red: 0.36, green: 0.22, blue: 0.0))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ТекстыНастроекСервера.т("close"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(red: 1.0, green: 0.95, blue: 0.80))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(red: 0.94, green: 0.84, blue: 0.54))
                .frame(height: 1)
        }
    }
}

/// Окно «Обновите приложение»: не блокирует — «Позже» закрывает, следующее не раньше чем через сутки.
private struct ОкноОбновленияПриложения: View {
    let ссылка: URL
    let закрыть: () -> Void
    @Environment(\.openURL) private var открытьСсылку

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.down.app.fill")
                .font(.system(size: 46))
                .foregroundStyle(Color(red: 0.04, green: 0.42, blue: 0.24))
            Text(ТекстыНастроекСервера.т("upd_title"))
                .font(.system(size: 20, weight: .bold))
                .multilineTextAlignment(.center)
            Text(ТекстыНастроекСервера.т("upd_text"))
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                открытьСсылку(ссылка)
                закрыть()
            } label: {
                Text(ТекстыНастроекСервера.т("upd_go"))
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.04, green: 0.42, blue: 0.24))
            Button(action: закрыть) {
                Text(ТекстыНастроекСервера.т("upd_later"))
                    .font(.system(size: 15, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(24)
        .presentationDetents([.medium])
    }
}

/// Подписи слоя на языке телефона (kk/ru/en/ar) — тем же способом, что SystemText.
enum ТекстыНастроекСервера {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? тексты["ru"]!
        return словарь[ключ] ?? тексты["ru"]![ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": [
            "close": "Закрыть",
            "upd_title": "Обновите приложение",
            "upd_text": "Вышла новая версия Kliko. Обновитесь в App Store, чтобы всё работало как надо.",
            "upd_go": "Обновить",
            "upd_later": "Позже",
            "force_text": "Эта версия Kliko устарела. Чтобы продолжить, установите обновление из App Store.",
            "warn_title": "Эта версия устарела",
            "warn_text": "Через {n} ч без обновления приложение перестанет работать. Установите новую версию из App Store.",
            "warn_left_h": "Осталось {n} ч",
            "warn_left_d": "Осталось {n} дн."
        ],
        "kk": [
            "close": "Жабу",
            "upd_title": "Қосымшаны жаңартыңыз",
            "upd_text": "Kliko-ның жаңа нұсқасы шықты. Бәрі дұрыс жұмыс істеуі үшін App Store-да жаңартыңыз.",
            "upd_go": "Жаңарту",
            "upd_later": "Кейінірек",
            "force_text": "Kliko-ның бұл нұсқасы ескірді. Жалғастыру үшін App Store-дан жаңартуды орнатыңыз.",
            "warn_title": "Бұл нұсқа ескірді",
            "warn_text": "Жаңартпасаңыз, {n} сағаттан кейін қосымша жұмысын тоқтатады. App Store-дан жаңа нұсқаны орнатыңыз.",
            "warn_left_h": "{n} сағ қалды",
            "warn_left_d": "{n} күн қалды"
        ],
        "en": [
            "close": "Close",
            "upd_title": "Update the app",
            "upd_text": "A new version of Kliko is available. Update in the App Store to keep everything working.",
            "upd_go": "Update",
            "upd_later": "Later",
            "force_text": "This version of Kliko is out of date. To continue, install the update from the App Store.",
            "warn_title": "This version is out of date",
            "warn_text": "Without an update, the app will stop working in {n} hours. Install the new version from the App Store.",
            "warn_left_h": "{n} h left",
            "warn_left_d": "{n} days left"
        ],
        "ar": [
            "close": "إغلاق",
            "upd_title": "حدّث التطبيق",
            "upd_text": "يتوفر إصدار جديد من Kliko. حدّث التطبيق من App Store ليعمل كل شيء كما ينبغي.",
            "upd_go": "تحديث",
            "upd_later": "لاحقًا",
            "force_text": "هذا الإصدار من Kliko قديم. للمتابعة، ثبّت التحديث من App Store.",
            "warn_title": "هذا الإصدار قديم",
            "warn_text": "بدون تحديث سيتوقف التطبيق عن العمل خلال {n} ساعة. ثبّت الإصدار الجديد من App Store.",
            "warn_left_h": "متبقٍ {n} ساعة",
            "warn_left_d": "متبقٍ {n} يوم"
        ]
    ]
}
