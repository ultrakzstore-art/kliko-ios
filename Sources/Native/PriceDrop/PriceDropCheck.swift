import SwiftUI
import UIKit
import UserNotifications

/**
 СНИЖЕНИЕ ЦЕНЫ В ИЗБРАННОМ — ЭТАП 21 ПЕРЕХОДА НА SWIFTUI (владелец 25.09.2026: «следующие этапы»).

 То же фоновое задание, что проверяет сохранённые поиски (ПроверкаПоисков, BGAppRefreshTask этапа 12), после поисков
 спрашивает у сайта до 10 объявлений из избранного — давно проверенные первыми (FavoritesStore.кПроверкеЦены) — тем же
 GET /api/listings.php?id=, что карточка (ListingsAPI.объявлениеСОтветом, с куками, взятыми заранее с пределом по
 времени). Цена ниже, чем в снимке избранного, — ОДНО локальное уведомление на все снижения: «Цена снизилась: «iPhone
 15» — 450 000 ₸ → 399 000 ₸ +2 ещё». Снимок получает свежую цену (и копия карточки этапа 13, если она есть), так что о
 том же снижении второй раз не скажем. Нажатие открывает объявление нативно — через роутер ссылок этапа 8 (.объявление),
 по метке в userInfo, как уведомление сохранённого поиска (AppDelegate).

 🔴 ТОЛЬКО С РАЗРЕШЁННЫМИ УВЕДОМЛЕНИЯМИ. Запрещены — задание не тратит ни сеть, ни батарею (ПроверкаПоисков.проверить):
 цены в снимках не трогаем, и после разрешения первая проверка расскажет о снижении с последней увиденной цены.

 🔴 В ПРЕДЕЛАХ ВРЕМЕНИ ЗАДАНИЯ. Запросы — по одному; перед каждым смотрим на отмену (expirationHandler) и на общий срок
 проверки. Срок вышел — проверенное отмечаем и о найденном говорим; задание отменено системой — не трогаем ничего:
 новые цены без уведомления похоронили бы снижение. Закрывает задание ровно один раз РазовоеЗавершение этапа 12.

 Включается в кабинете переключателем (по умолчанию включено; UserDefaults, стирается при выходе вместе с избранным и
 датами проверок в нём). Новых адресов на сайте нет.
 */
enum СнижениеЦены {
    /// Выбор человека в кабинете (РазделСниженияЦены, @AppStorage). Нет записи — включено.
    static let ключ = "kliko.pricedrop.on"
    /// Объявлений за один фоновый запуск.
    static let заРаз = 10
    /// Значение метки ПроверкаПоисков.метка в userInfo своего уведомления.
    static let меткаЦены = "price_drop"
    /// Одно уведомление на все снижения: новое заменяет прежнее, а не копится стопкой.
    static let номерУведомления = "kz.kliko.app.price-drop"

    static var включено: Bool {
        (UserDefaults.standard.object(forKey: ключ) as? Bool) ?? true
    }

    /// Есть что проверять: рубильники, выбор в кабинете и хоть одно объявление в избранном.
    @MainActor
    static var нужнаПроверка: Bool {
        Config.снижениеЦены && Config.избранное && включено && !FavoritesStore.shared.товары.isEmpty
    }

    // MARK: - Проверка

    /// Проверка цены избранного. true — отработала (даже если снижений нет); false — сеть не пустила ни одного запроса
    /// или задание отменено.
    @MainActor
    static func проверить(куки: [String: String], до край: Date) async -> Bool {
        guard нужнаПроверка else { return true }
        let очередь = FavoritesStore.shared.кПроверкеЦены(заРаз)
        var свежие: [Listing] = []
        var проверены = Set<String>()
        for товар in очередь {
            guard !Task.isCancelled, Date() < край else { break }
            let взятое = ListingDetailCache.поколение      // до запроса: ответ, опоздавший за выходом, на диск не ляжет
            do {
                let ответ = try await ListingsAPI.объявлениеСОтветом(товар.id, куки: куки)
                проверены.insert(товар.id)
                /* Номер в ответе обязан совпасть: иначе сайт отдал не то, и цену им не переписываем. */
                guard ответ.товар.id == товар.id else { continue }
                свежие.append(ответ.товар)
                /* Копия карточки без сети (этап 13) — свежей, если она есть; новых копий фоновая проверка не заводит. */
                if Config.карточкиБезСети && ListingDetailCache.есть(товар.id) {
                    ListingDetailCache.записать(ответ.сырое, id: товар.id, поколение: взятое)
                }
            } catch let ошибка as ListingsAPI.Ошибка {
                /* Нет связи — не отмечаем: в следующий раз это объявление снова первое. Сайт ответил (404, не тот
                   ответ) — отмечаем проверенным, иначе снятое с продажи вечно стояло бы в начале очереди. */
                if case .сеть = ошибка { continue }
                проверены.insert(товар.id)
            } catch {
                continue
            }
        }
        guard !Task.isCancelled, !проверены.isEmpty else { return false }
        let снижения = FavoritesStore.shared.отметитьПроверкуЦен(свежие, проверены: проверены)
        await ИзбранноеФайл.дождаться()
        guard !снижения.isEmpty else { return true }
        await уведомить(снижения)
        return true
    }

    /// Цена, которую сравниваем: у аренды — за сутки, иначе цена продажи; нет или ноль — nil (сравнивать нечего).
    static func цена(_ з: ИзбранноеЗапись) -> Double? {
        if з.forRent {
            guard let день = з.rentPriceDay, день > 0 else { return nil }
            return день
        }
        guard let p = з.price, p > 0 else { return nil }
        return p
    }

    /// Снизилась ли цена от снимка к свежей записи. Продажа стала арендой (или наоборот) — это не снижение.
    static func сравнить(_ было: ИзбранноеЗапись, _ стало: ИзбранноеЗапись) -> СнижениеЦеныНайдено? {
        guard было.forRent == стало.forRent, let прежняя = цена(было), let нынешняя = цена(стало),
              нынешняя < прежняя else { return nil }
        let название = стало.title.isEmpty ? было.title : стало.title
        return СнижениеЦеныНайдено(id: стало.id, название: название, было: прежняя, стало: нынешняя,
                                   аренда: стало.forRent)
    }

    // MARK: - Уведомление

    /// Одно уведомление: самое большое снижение (в долях от цены) и «+N ещё». Нажатие открывает его.
    @MainActor
    private static func уведомить(_ снижения: [СнижениеЦеныНайдено]) async {
        let порядок = снижения.sorted { $0.доля > $1.доля }
        guard let главное = порядок.first else { return }
        let содержимое = UNMutableNotificationContent()
        содержимое.title = PriceDropText.т("notif_title")
        let название = главное.название.isEmpty ? PriceDropText.т("untitled") : главное.название
        var текст = String(format: PriceDropText.т("notif_item"), название, сумма(главное.было, аренда: главное.аренда),
                           сумма(главное.стало, аренда: главное.аренда))
        if порядок.count > 1 {
            текст += " " + String(format: PriceDropText.т("notif_more"), порядок.count - 1)
        }
        содержимое.body = текст
        содержимое.sound = .default
        содержимое.threadIdentifier = номерУведомления
        содержимое.userInfo = [ПроверкаПоисков.метка: меткаЦены, "id": главное.id]
        let запрос = UNNotificationRequest(identifier: номерУведомления, content: содержимое, trigger: nil)
        await withCheckedContinuation { (готово: CheckedContinuation<Void, Never>) in
            UNUserNotificationCenter.current().add(запрос) { _ in готово.resume() }
        }
    }

    /// «450 000 ₸», у аренды — «5 000 ₸/сут»: как на карточке (ListingCard).
    @MainActor
    private static func сумма(_ n: Double, аренда: Bool) -> String {
        ListingCard.тенге(n) + (аренда ? FeedText.т("perday") : "")
    }

    // MARK: - Нажатие

    /// Нажатие на уведомление (AppDelegate): номер объявления. nil — уведомление не о снижении цены.
    static func номер(из info: [AnyHashable: Any]) -> String? {
        guard (info[ПроверкаПоисков.метка] as? String) == меткаЦены, let номер = info["id"] as? String,
              номер.range(of: "^[A-Za-z0-9_-]{1,40}$", options: .regularExpression) != nil else { return nil }
        return номер
    }

    /// Объявление — нативной карточкой через роутер ссылок этапа 8; вкладок нет — страница объявления на сайте.
    @MainActor
    static func открыть(_ номер: String) {
        WebBridge.shared.открытьЭкран(.объявление(id: номер), запасной: Listing(номер: номер).адрес)
    }

    // MARK: - Выход

    /// Выход из аккаунта (WebContainer, bye=1): уведомление о чужом избранном убираем, выбор в кабинете — к исходному.
    /// Даты проверок лежат в записях избранного и стираются вместе с ним.
    static func стереть() {
        UserDefaults.standard.removeObject(forKey: ключ)
        let центр = UNUserNotificationCenter.current()
        центр.removePendingNotificationRequests(withIdentifiers: [номерУведомления])
        центр.removeDeliveredNotifications(withIdentifiers: [номерУведомления])
    }
}

/// Найденное снижение: объявление, прежняя и нынешняя цена.
struct СнижениеЦеныНайдено {
    let id: String
    let название: String
    let было: Double
    let стало: Double
    let аренда: Bool

    /// Насколько снизилась, долей от прежней: 0,2 — на 20 %.
    var доля: Double { было > 0 ? (было - стало) / было : 0 }
}

/**
 Раздел кабинета «Снижение цены» (этап 21) — рядом с сохранёнными поисками: одно задание, одни условия. Переключатель
 и что ему мешает: запрещённые уведомления и выключенное «Обновление контента».
 */
struct РазделСниженияЦены: View {
    @AppStorage(СнижениеЦены.ключ) private var включено = true
    /// Разрешены ли уведомления — кабинет уже спрашивает систему (ДанныеТелефона.статусУведомлений). nil — не знаем.
    let уведомления: UNAuthorizationStatus?

    init(уведомления: UNAuthorizationStatus?) {
        self.уведомления = уведомления
    }

    var body: some View {
        Section {
            Toggle(isOn: $включено) {
                Label {
                    Text(PriceDropText.т("toggle"))
                } icon: {
                    Image(systemName: "arrow.down.circle").foregroundStyle(Theme.green2)
                }
            }
            .tint(Theme.green2)
        } header: {
            Text(PriceDropText.т("title"))
        } footer: {
            Text(подпись)
        }
        /* Включили — задание в расписание и, если человек ещё не отвечал, вопрос про уведомления; выключили —
           расписание снимется, если и поисков нет. */
        .onChange(of: включено) { _, стало in
            ПроверкаПоисков.запланировать()
            if стало { Task { await ПроверкаПоисков.попроситьРазрешение() } }
        }
    }

    /// Сначала — что мешает проверке (только когда она включена), потом — как она работает.
    private var подпись: String {
        var части: [String] = []
        if включено {
            if уведомления == .denied { части.append(PriceDropText.т("notif_off")) }
            if UIApplication.shared.backgroundRefreshStatus != .available { части.append(PriceDropText.т("refresh_off")) }
        }
        части.append(String(format: PriceDropText.т("footer"), СнижениеЦены.заРаз))
        return части.joined(separator: "\n\n")
    }
}
