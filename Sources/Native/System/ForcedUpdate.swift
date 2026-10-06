import Foundation
import SwiftUI
import UIKit

/// ОБНОВЛЕНИЕ ПО ВЕРСИИ APP STORE (владелец 06.10.2026: «когда приложение отстало на 3 обновления — принудительное
/// обновление»).
///
/// Последнюю версию в App Store узнаём у Apple: GET itunes.apple.com/lookup?bundleId=kz.kliko.app&country=kz
/// (results[0].version и trackViewUrl) — при запуске и возврате в приложение, не чаще раза в 6 часов. Последний ответ
/// лежит в UserDefaults. Нет сети и нет сохранённого ответа — ничего не показываем и ничего не блокируем.
///
/// Отставание — сколько выпусков между своей версией и версией App Store: для «1.N» это N магазина минус свой N, мажор
/// магазина больше — считаем «много». Своя версия выше магазинной (TestFlight) или равна — отставание 0.
///
/// Ступени (порог — force_lag из админки, по умолчанию 3; 0 — принудительное выключено):
///  • 1 … порог−1 — мягкое окно «Обновите приложение» раз в сутки (то же, что по min_version, RemoteSettings.swift);
///  • порог и больше — предупреждение «Эта версия устарела» с обратным отсчётом, «Обновить» и «Позже», не чаще раза
///    в 6 часов. Момент, когда отставание впервые дошло до порога, хранится в UserDefaults и новыми выпусками в App Store
///    не сбрасывается — только обновлением самого приложения (отставание стало ниже порога);
///  • через force_grace_hours (по умолчанию 72) часов после этого момента — полный экран без закрытия.
/// Окна живут в отдельном окне UIKit над всем приложением (SceneDelegate): их не закрывают листы и экраны поверх ленты.
enum ВерсияВМагазине {
    static let ключВерсии = "kliko.appStore.version"
    static let ключСсылки = "kliko.appStore.url"
    static let ключПроверки = "kliko.appStore.checkedAt"
    private static let адресЗапроса = URL(string: "https://itunes.apple.com/lookup?bundleId=kz.kliko.app&country=kz")!

    /// Ответ App Store: версия и ссылка, или пусто (приложения в выдаче нет).
    struct ОтветМагазина {
        let версия: String?
        let ссылка: String?
    }

    /// Версия этой сборки (MARKETING_VERSION).
    static var своя: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    /// Последняя известная версия в App Store или nil — ни разу не узнавали или App Store отдал пустой ответ.
    static var магазинная: String? {
        guard let в = UserDefaults.standard.string(forKey: ключВерсии), !в.isEmpty else { return nil }
        return в
    }

    /// Порог принудительного обновления в выпусках: force_lag сервера, по умолчанию 3; 0 — выключено.
    static var порог: Int { НастройкиСервера.целоеЧисло("force_lag") ?? 3 }

    /// Сколько часов предупреждаем до запрета: force_grace_hours сервера, по умолчанию 72 (не больше года).
    static var срокЧасов: Int { min(НастройкиСервера.целоеЧисло("force_grace_hours") ?? 72, 24 * 365) }

    /// Сколько выпусков между своей и магазинной версией. Своя не ниже — 0; мажор магазина больше — 99;
    /// отличие только в третьей цифре («1.10» и «1.10.1») — 1.
    static func отставание(своя: String, магазин: String) -> Int {
        guard НастройкиСервера.версия(своя, нижеЧем: магазин) else { return 0 }
        let а = своя.split(separator: ".").map { Int($0) ?? 0 }
        let б = магазин.split(separator: ".").map { Int($0) ?? 0 }
        let мажорА = а.first ?? 0
        let мажорБ = б.first ?? 0
        if мажорБ > мажорА { return 99 }
        let минорА = а.count > 1 ? а[1] : 0
        let минорБ = б.count > 1 ? б[1] : 0
        return max(минорБ - минорА, 1)
    }

    /// Отставание по последнему ответу App Store или nil — ответа нет.
    static func текущееОтставание() -> Int? {
        guard let м = магазинная else { return nil }
        return отставание(своя: своя, магазин: м)
    }

    /// Отстали на 1 … порог−1 выпусков (или принудительное выключено) — мягкое окно «Обновите приложение».
    static func мягкоеОтставание() -> Bool {
        guard let о = текущееОтставание(), о >= 1 else { return false }
        let п = порог
        return п == 0 || о < п
    }

    /// Ссылка «Обновить»: trackViewUrl из ответа App Store, иначе — из админки или по умолчанию.
    static func ссылка() -> URL {
        if let т = UserDefaults.standard.string(forKey: ключСсылки),
           т.hasPrefix("https://apps.apple.com/") || т.hasPrefix("https://itunes.apple.com/"),
           let u = URL(string: т) {
            return u
        }
        return НастройкиСервера.ссылкаAppStore()
    }

    private static let сессия: URLSession = {
        let к = URLSessionConfiguration.ephemeral
        к.urlCache = nil
        к.requestCachePolicy = .reloadIgnoringLocalCacheData
        к.timeoutIntervalForRequest = 10
        return URLSession(configuration: к)
    }()

    /// Запрос к App Store. nil — нет сети, ошибка, не тот ответ: сохранённое не трогаем.
    static func загрузить() async -> ОтветМагазина? {
        var запрос = URLRequest(url: адресЗапроса, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        запрос.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let пара = try? await сессия.data(for: запрос),
              let http = пара.1 as? HTTPURLResponse, http.statusCode == 200,
              let объект = (try? JSONSerialization.jsonObject(with: пара.0)) as? [String: Any],
              let список = объект["results"] as? [Any] else { return nil }
        guard let первый = список.first as? [String: Any] else { return ОтветМагазина(версия: nil, ссылка: nil) }
        let версия = (первый["version"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let ссылка = первый["trackViewUrl"] as? String
        return ОтветМагазина(версия: (версия?.isEmpty ?? true) ? nil : версия, ссылка: ссылка)
    }

    /// Сохранить ответ. Пустой ответ стирает версию — блокировать нечем.
    static func запомнить(_ ответ: ОтветМагазина) {
        let д = UserDefaults.standard
        if let в = ответ.версия { д.set(в, forKey: ключВерсии) } else { д.removeObject(forKey: ключВерсии) }
        if let с = ответ.ссылка, !с.isEmpty { д.set(с, forKey: ключСсылки) }
        д.set(Date().timeIntervalSince1970, forKey: ключПроверки)
    }
}

/// Состояние предупреждения и запрета устаревшей версии. Окно над приложением показывает SceneDelegate.
@MainActor
final class ПринудительноеОбновление: ObservableObject {
    enum Показ: Equatable {
        case нет
        /// Отстали на порог и больше, срок ещё не вышел: можно закрыть.
        case предупреждение(срок: Date)
        /// Срок вышел: полный экран без закрытия.
        case запрет
    }

    static let shared = ПринудительноеОбновление()

    @Published private(set) var показ: Показ = .нет
    @Published private(set) var ссылка: URL = ВерсияВМагазине.ссылка()

    /// Когда отставание впервые дошло до порога (секунды с 1970) и какая версия была тогда в App Store.
    private let ключНачала = "kliko.forceUpdate.since"
    private let ключНачалаМагазин = "kliko.forceUpdate.sinceStore"
    /// Когда последний раз показывали предупреждение — следующее не раньше чем через 6 часов.
    private let ключПредупреждения = "kliko.forceUpdate.warnedAt"
    private var идёт = false
    /// Неудачный запрос — следующий не раньше чем через 10 минут (без сети не дёргаем Apple на каждом возврате).
    private var неудача: Date? = nil
    /// Пересчёт в момент окончания срока, если приложение открыто.
    private var таймерСрока: Task<Void, Never>? = nil

    private init() {
        пересчитать()
    }

    /// Запуск и возврат в приложение: сразу — по сохранённому ответу, App Store — не чаще раза в 6 часов.
    func проверить() async {
        пересчитать()
        if идёт { return }
        let проверяли = UserDefaults.standard.double(forKey: ВерсияВМагазине.ключПроверки)
        if Date().timeIntervalSince1970 - проверяли < 6 * 3600 { return }
        if let н = неудача, Date().timeIntervalSince(н) < 600 { return }
        идёт = true
        let ответ = await ВерсияВМагазине.загрузить()
        идёт = false
        guard let ответ else {
            неудача = Date()
            return
        }
        неудача = nil
        ВерсияВМагазине.запомнить(ответ)
        пересчитать()
        НастройкиСервераМодель.shared.пересчитатьОкноОбновления()
    }

    /// «Позже» на предупреждении: следующее — при запуске или возврате, но не раньше чем через 6 часов.
    func отложить() {
        if case .предупреждение = показ { показ = .нет }
    }

    private func пересчитать() {
        ссылка = ВерсияВМагазине.ссылка()
        let д = UserDefaults.standard
        let п = ВерсияВМагазине.порог
        guard п > 0, let о = ВерсияВМагазине.текущееОтставание(), о >= п else {
            // Обновились (или принудительное выключено, или ответа App Store нет) — отметка больше не нужна.
            д.removeObject(forKey: ключНачала)
            д.removeObject(forKey: ключНачалаМагазин)
            д.removeObject(forKey: ключПредупреждения)
            таймерСрока?.cancel()
            таймерСрока = nil
            показ = .нет
            return
        }
        let сейчас = Date()
        var начало = д.double(forKey: ключНачала)
        if начало <= 0 {
            начало = сейчас.timeIntervalSince1970
            д.set(начало, forKey: ключНачала)
            д.set(ВерсияВМагазине.магазинная, forKey: ключНачалаМагазин)
        }
        let срок = Date(timeIntervalSince1970: начало + Double(ВерсияВМагазине.срокЧасов) * 3600)
        if сейчас >= срок {
            таймерСрока?.cancel()
            таймерСрока = nil
            показ = .запрет
            return
        }
        поставитьТаймер(до: срок)
        if case .предупреждение = показ {
            показ = .предупреждение(срок: срок)
            return
        }
        let было = д.double(forKey: ключПредупреждения)
        if сейчас.timeIntervalSince1970 - было >= 6 * 3600 {
            д.set(сейчас.timeIntervalSince1970, forKey: ключПредупреждения)
            показ = .предупреждение(срок: срок)
        } else {
            показ = .нет
        }
    }

    private func поставитьТаймер(до срок: Date) {
        таймерСрока?.cancel()
        let секунды = max(1, срок.timeIntervalSinceNow) + 1
        таймерСрока = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(секунды * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.пересчитать()
        }
    }
}

/// Содержимое окна над приложением: предупреждение с отсчётом или полный экран запрета.
struct СлойОбновленияПриложения: View {
    @ObservedObject private var обновление = ПринудительноеОбновление.shared

    private var справаНалево: Bool {
        (Locale.preferredLanguages.first ?? "ru").hasPrefix("ar")
    }

    var body: some View {
        Group {
            switch обновление.показ {
            case .нет:
                Color.clear
            case .предупреждение(let срок):
                ПредупреждениеОбУстаревании(срок: срок, ссылка: обновление.ссылка) { обновление.отложить() }
            case .запрет:
                ЭкранЗапретаВерсии(ссылка: обновление.ссылка)
            }
        }
        .environment(\.layoutDirection, справаНалево ? .rightToLeft : .leftToRight)
    }
}

/// Значок окон обновления: зелёный квадрат с градиентом шапки сайта.
private struct ЗначокОбновления: View {
    let символ: String

    var body: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(LinearGradient(colors: [Theme.шапкаВерх, Theme.шапкаНиз], startPoint: .top, endPoint: .bottom))
            .frame(width: 84, height: 84)
            .overlay {
                Image(systemName: символ)
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: Color.black.opacity(0.12), radius: 10, y: 4)
    }
}

/// Кнопка «Обновить»: зелёная, во всю ширину.
private struct КнопкаОбновить: View {
    let ссылка: URL

    var body: some View {
        Button {
            UIApplication.shared.open(ссылка)
        } label: {
            Text(ТекстыНастроекСервера.т("upd_go"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Theme.зелёный, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Предупреждение: версия устарела, через срок перестанет работать; «Обновить» и «Позже».
private struct ПредупреждениеОбУстаревании: View {
    let срок: Date
    let ссылка: URL
    let позже: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
            VStack(spacing: 14) {
                ЗначокОбновления(символ: "clock.badge.exclamationmark")
                Text(ТекстыНастроекСервера.т("warn_title"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.текст)
                    .multilineTextAlignment(.center)
                Text(ТекстыНастроекСервера.т("warn_text")
                        .replacingOccurrences(of: "{n}", with: String(ВерсияВМагазине.срокЧасов)))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.текстВторой)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                TimelineView(.periodic(from: .now, by: 60)) { контекст in
                    Text(Self.осталось(до: срок, сейчас: контекст.date))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.золото)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Theme.золото.opacity(0.14), in: Capsule())
                }
                КнопкаОбновить(ссылка: ссылка)
                    .padding(.top, 4)
                Button(action: позже) {
                    Text(ТекстыНастроекСервера.т("upd_later"))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.текстВторой)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            .padding(24)
            .frame(maxWidth: 420)
            .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, 20)
        }
    }

    /// «Осталось N ч», больше двух суток — «Осталось N дн.».
    static func осталось(до срок: Date, сейчас: Date) -> String {
        let часы = max(0, Int((срок.timeIntervalSince(сейчас) / 3600).rounded(.up)))
        if часы > 48 {
            let дни = Int((Double(часы) / 24).rounded(.up))
            return ТекстыНастроекСервера.т("warn_left_d").replacingOccurrences(of: "{n}", with: String(дни))
        }
        return ТекстыНастроекСервера.т("warn_left_h").replacingOccurrences(of: "{n}", with: String(часы))
    }
}

/// Запрет: версия устарела, продолжить можно только обновившись. Закрыть нельзя.
private struct ЭкранЗапретаВерсии: View {
    let ссылка: URL

    var body: some View {
        ZStack {
            Theme.фонСтраницы
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Spacer()
                ЗначокОбновления(символ: "arrow.down.app.fill")
                Text(ТекстыНастроекСервера.т("upd_title"))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.текст)
                    .multilineTextAlignment(.center)
                Text(ТекстыНастроекСервера.т("force_text"))
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.текстВторой)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                КнопкаОбновить(ссылка: ссылка)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: 480)
        }
        .accessibilityAddTraits(.isModal)
    }
}
