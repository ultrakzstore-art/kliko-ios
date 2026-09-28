import Foundation
import StoreKit
import CryptoKit
import Combine

/**
 ПЛАТНЫЕ УСЛУГИ ЧЕРЕЗ APP STORE (StoreKit 2). Решение владельца: цифровые услуги в iOS-приложении продаются только
 через In-App Purchase по правилам App Store, сайт продаёт их картой как раньше.

 Правило App Store 3.1.1: цифровые услуги внутри iOS-приложения продаются только через In-App Purchase. Поэтому здесь
 нет ни кошелька сайта, ни оплаты картой (promote_item, buy_slots, buy_combo, buy_pro, buy_ai_package, top_preset в
 submit — всё это сайт списывает с кошелька). Приложение покупает у Apple, а услугу включает сайт по подписанному
 Apple чеку (JWS) через POST /api/apple_iap.php — спецификация сервера: docs/APPLE_IAP_SERVER.md.

 Всё выключено рубильником Config.цифровыеПокупки (false). Выключен — ни StoreKit, ни слушателя, ни запросов; экраны
 показывают только сведения и текст сайта «Эта возможность недоступна в приложении.». Ссылок и кнопок оплаты на сайте
 в приложении нет ни при false, ни при true (правила 3.1.1 и 3.1.3): ни адресов оплаты, ни слов «дешевле на сайте».

 ПОРЯДОК ПОКУПКИ
   1. Product.products(for:) — товары и их цены из App Store. Цена на экране — только product.displayPrice (валюта и
      формат витрины человека); тенге сайта в приложении не показываются нигде.
   2. product.purchase(options: [.appAccountToken(токен)]) — токен выводится из id пользователя сайта (KlikoUser.id,
      «u<12 hex>») так, что сервер посчитает его сам (ПродуктыApple.токен, алгоритм — в docs/APPLE_IAP_SERVER.md, §2).
      По нему сервер понимает, чья покупка, даже если чек пришёл уведомлением Apple без сессии.
   3. Подтверждённая транзакция (VerificationResult.verified) уходит на сайт: jws (VerificationResult.jwsRepresentation),
      product, service, key, target_id (объявление или резюме), transaction_id. Сайт сам проверяет подпись у Apple.
   4. transaction.finish() — только когда сайт ответил ok (или прямо велел закрыть: finish). Любой сбой — транзакция
      остаётся незакрытой у Apple, человек видит «Покупка сохранится и применится позже», а приложение повторяет:
      при следующем запуске (Transaction.unfinished), при входе в аккаунт и из «Восстановить покупки». Повтор безопасен:
      сайт отвечает по transaction_id идемпотентно. Оплаченная транзакция не теряется никогда.
   5. Transaction.updates слушается с запуска приложения (AppDelegate): одобренные «Попросить купить», продления PRO,
      покупки с другого устройства, возвраты — всё идёт тем же путём на сайт.
   6. «Восстановить покупки» — AppStore.sync(), затем Transaction.currentEntitlements (действующий PRO) и незакрытые.

 Какому объявлению услуга, запоминается на телефоне до ответа сайта (UserDefaults: по transaction_id и, до покупки,
 по product id — для «Попросить купить», когда транзакция придёт позже через Transaction.updates). Выход из аккаунта
 это не стирает: оплаченное не должно пропасть.
 */

// MARK: - Какие услуги и какие товары

/// Услуга сайта, которую покупает товар App Store. rawValue — поле service запроса на сайт.
enum ВидУслугиApple: String, CaseIterable {
    /// ТОП и поднятия объявления (PROMO_CFG.packages, promote_item). Нужен target_id — id объявления.
    case продвижение = "promo"
    /// Kliko PRO (PRO_TIERS, buy_pro). Подписка с автопродлением.
    case про = "pro"
    /// Тариф слотов на 30 дней (slots.tiers из my_items, buy_slots).
    case слоты = "slots"
    /// Комбо-пакет: слоты + Kliko AI (COMBO_PACKS, buy_combo).
    case комбо = "combo"
    /// Пакет Kliko AI (AI_PACKS, buy_ai_package).
    case пакетИИ = "ai"
    /// «В ТОП» резюме на 7 дней (/api/jobs.php?action=promote). Нужен target_id — id резюме.
    case топРезюме = "resume_top"

    /// Услуга привязана к одной записи — объявлению или резюме.
    var нуженОбъект: Bool { self == .продвижение || self == .топРезюме }

    /// Значок кнопки покупки.
    var значок: String {
        switch self {
        case .продвижение: return "arrow.up.circle"
        case .про: return "crown.fill"
        case .слоты: return "square.stack.3d.up"
        case .комбо: return "square.stack.3d.up.fill"
        case .пакетИИ: return "sparkles"
        case .топРезюме: return "arrow.up"
        }
    }
}

/// Тип товара в App Store Connect.
enum ТипТовараApple: String {
    /// Consumable — разовая услуга; покупать можно сколько угодно раз.
    case расходуемый = "consumable"
    /// Auto-Renewable Subscription — PRO, группа подписок «Kliko PRO».
    case подписка = "auto_renewable"
}

/// Товар App Store и услуга сайта за ним. ключ — ключ сайта: preset PROMO_CFG, pack AI_PACKS / COMBO_PACKS, key
/// тарифа PRO, число слотов.
struct ТоварApple: Identifiable, Equatable {
    let id: String
    let вид: ВидУслугиApple
    let ключ: String
    let тип: ТипТовараApple
}

/**
 ВСЕ ТОВАРЫ — В ОДНОМ МЕСТЕ. Их надо завести в App Store Connect (Приложение → Монетизация → Встроенные покупки и
 Подписки) с ЭТИМИ product id, байт в байт. Цены App Store задаёт ценовыми точками по витринам: ниже — цена сайта в
 тенге, от которой подобрать ближайшую точку витрины Казахстана (Apple удерживает комиссию 15 % по программе малого
 бизнеса или 30 %; поднимать ли цену — решает владелец). Название и описание — на русском и казахском.

 РАЗОВЫЕ (Consumable), продвижение объявления (нужен target_id):
   kz.kliko.app.promo.top3      «ТОП 3 дня»                        сайт 1 000 ₸
   kz.kliko.app.promo.combo7    «Комбо: ТОП 7д + 2 подъёма»        сайт 2 830 ₸
   kz.kliko.app.promo.top14b5   «ТОП 14 дней + 5 подъёмов»         сайт 5 580 ₸
   kz.kliko.app.promo.top30b9   «ТОП 30 дней + 9 подъёмов»         сайт 10 080 ₸
   kz.kliko.app.promo.bump1     «Поднятие» (1 подъём)              сайт 550 ₸ (bump_price)
 РАЗОВЫЕ (Consumable), резюме (нужен target_id):
   kz.kliko.app.resume.top7     «Резюме в ТОП на 7 дней»           цену на сайте не видно — задать владельцу
 РАЗОВЫЕ (Consumable), срок 30 / 7 / 90 дней считает сайт:
   kz.kliko.app.slots.10        «+10 слотов на 30 дней»            по slots.tiers сайта (цена тарифа)
   kz.kliko.app.slots.25        «+25 слотов на 30 дней»            по slots.tiers сайта
   kz.kliko.app.slots.50        «+50 слотов на 30 дней»            по slots.tiers сайта
   kz.kliko.app.slots.100       «+100 слотов на 30 дней»           по slots.tiers сайта
     id тарифа слотов — «kz.kliko.app.slots.» + число slots из tiers[] ответа my_items. Экран сам ищет товар под
     каждый тариф сайта; заводить надо ровно те числа, что отдаёт сервер (в снимке их нет — сверить на сервере).
   kz.kliko.app.combo.start     «Комбо Старт: 20 слотов + Kliko AI 7 дн»    сайт 9 500 ₸
   kz.kliko.app.combo.active    «Комбо Актив: 50 слотов + Kliko AI 14 дн»   сайт 19 500 ₸
   kz.kliko.app.combo.max       «Комбо Макс: 100 слотов + Kliko AI 30 дн»   сайт 29 500 ₸
   kz.kliko.app.ai.week         «Kliko AI на 7 дней»               сайт 4 500 ₸
   kz.kliko.app.ai.month        «Kliko AI на 30 дней»              сайт 13 500 ₸
   kz.kliko.app.ai.quarter      «Kliko AI на 90 дней»              сайт 34 500 ₸
 ПОДПИСКА (Auto-Renewable), группа «Kliko PRO»:
   kz.kliko.app.pro.business.month   «Kliko PRO» (PRO_TIERS level 1, key business), 1 месяц   сайт 17 900 ₸ / мес
     Появятся уровни 2 и 3 (PRO_SLOTS знает 1, 2, 3) — kz.kliko.app.pro.<key>.month в той же группе, уровнем выше.

 Пакеты на срок (слоты, комбо, Kliko AI) заведены как Consumable по решению владельца: срок и продление считает сайт,
 как при покупке за кошелёк. Apple допускает для таких и Non-Renewing Subscription — код одинаково работает с обоими
 типами (сайт всё равно получает каждую транзакцию); меняется только тип при создании товара.
 */
enum ПродуктыApple {
    static let префикс = "kz.kliko.app."
    /// Адрес сайта, который включает услугу по чеку Apple (docs/APPLE_IAP_SERVER.md). От корня, без языка.
    static let адресСервера = "/api/apple_iap.php"
    /// Bundle ID приложения — его же сверяет сервер в чеке (bundleId).
    static let bundleID = "kz.kliko.app"

    /// ТОП при подаче объявления сайт списывает с кошелька (top_preset в submit). Через App Store так нельзя: продвижение
    /// покупается после публикации, уже для готового объявления. Поэтому при Config.цифровыеПокупки = true мастер
    /// подачи ТОП не предлагает, а экран «Опубликовано» даёт кнопку «Продвинуть объявление». false — навсегда.
    static let топПодачиСКошелька = false

    /**
     Промокод клуба основателей (redeem_coupon) при Config.цифровыеПокупки. Выключен: промокод даёт скидку «на
     продвижение и слоты» по ценам сайта, а в приложении те же услуги продаются по ценам App Store — скидка к ним не
     применяется, и поле кода, которое меняет цену покупки вне App Store, App Review может счесть обходом In-App
     Purchase (правила 3.1.1 и 3.1.3). Включать (true), только если сервер применяет код и к покупкам Apple (например,
     начисляет бонусные дни после чека apple_iap.php) — тогда это не скидка на оплату на сайте.
     */
    static let промокодКлуба = false

    static let все: [ТоварApple] = [
        ТоварApple(id: префикс + "promo.top3", вид: .продвижение, ключ: "top3", тип: .расходуемый),
        ТоварApple(id: префикс + "promo.combo7", вид: .продвижение, ключ: "combo7", тип: .расходуемый),
        ТоварApple(id: префикс + "promo.top14b5", вид: .продвижение, ключ: "top14b5", тип: .расходуемый),
        ТоварApple(id: префикс + "promo.top30b9", вид: .продвижение, ключ: "top30b9", тип: .расходуемый),
        ТоварApple(id: префикс + "promo.bump1", вид: .продвижение, ключ: "bump1", тип: .расходуемый),
        ТоварApple(id: префикс + "resume.top7", вид: .топРезюме, ключ: "top7", тип: .расходуемый),
        ТоварApple(id: префикс + "slots.10", вид: .слоты, ключ: "10", тип: .расходуемый),
        ТоварApple(id: префикс + "slots.25", вид: .слоты, ключ: "25", тип: .расходуемый),
        ТоварApple(id: префикс + "slots.50", вид: .слоты, ключ: "50", тип: .расходуемый),
        ТоварApple(id: префикс + "slots.100", вид: .слоты, ключ: "100", тип: .расходуемый),
        ТоварApple(id: префикс + "combo.start", вид: .комбо, ключ: "start", тип: .расходуемый),
        ТоварApple(id: префикс + "combo.active", вид: .комбо, ключ: "active", тип: .расходуемый),
        ТоварApple(id: префикс + "combo.max", вид: .комбо, ключ: "max", тип: .расходуемый),
        ТоварApple(id: префикс + "ai.week", вид: .пакетИИ, ключ: "week", тип: .расходуемый),
        ТоварApple(id: префикс + "ai.month", вид: .пакетИИ, ключ: "month", тип: .расходуемый),
        ТоварApple(id: префикс + "ai.quarter", вид: .пакетИИ, ключ: "quarter", тип: .расходуемый),
        ТоварApple(id: префикс + "pro.business.month", вид: .про, ключ: "business", тип: .подписка),
    ]

    /// Товары одной услуги, в порядке каталога.
    static func товары(_ вид: ВидУслугиApple) -> [ТоварApple] {
        все.filter { $0.вид == вид }
    }

    /// Товар по product id. Тариф слотов, которого нет в каталоге, — по числу в хвосте id.
    static func товар(_ id: String) -> ТоварApple? {
        if let известный = все.first(where: { $0.id == id }) { return известный }
        let начало = префикс + "slots."
        if id.hasPrefix(начало) {
            let хвост = String(id.dropFirst(начало.count))
            if let число = Int(хвост), число > 0 {
                return ТоварApple(id: id, вид: .слоты, ключ: String(число), тип: .расходуемый)
            }
        }
        return nil
    }

    /// Товар тарифа слотов сайта: «kz.kliko.app.slots.» + число слотов.
    static func товарСлотов(_ слотов: Int) -> ТоварApple {
        ТоварApple(id: префикс + "slots." + String(слотов), вид: .слоты, ключ: String(слотов), тип: .расходуемый)
    }

    /// Товар по ключу сайта (preset, pack, key тарифа).
    static func товар(_ вид: ВидУслугиApple, ключ: String) -> ТоварApple? {
        if вид == .слоты, let число = Int(ключ) { return товарСлотов(число) }
        return все.first(where: { $0.вид == вид && $0.ключ == ключ })
    }

    /**
     appAccountToken из id пользователя сайта. Сервер считает то же самое (docs/APPLE_IAP_SERVER.md, §2):
       байты = первые 16 байт SHA-256 от строки "kliko.kz/apple-iap/" + uid (UTF-8);
       байт 6 = (байт 6 AND 0x0F) OR 0x50 — версия 5; байт 8 = (байт 8 AND 0x3F) OR 0x80 — вариант RFC 4122;
       UUID строкой — строчными буквами, через дефисы 8-4-4-4-12.
     Секрета в нём нет и не нужно: токен только говорит, на чей аккаунт зачислить, а подпись чека проверяет сервер.
     */
    static func токен(для uid: String) -> UUID? {
        let чистый = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !чистый.isEmpty, let данные = ("kliko.kz/apple-iap/" + чистый).data(using: .utf8) else { return nil }
        var б = Array(SHA256.hash(data: данные))
        guard б.count >= 16 else { return nil }
        б[6] = (б[6] & 0x0F) | 0x50
        б[8] = (б[8] & 0x3F) | 0x80
        let байты: uuid_t = (б[0], б[1], б[2], б[3], б[4], б[5], б[6], б[7],
                              б[8], б[9], б[10], б[11], б[12], б[13], б[14], б[15])
        return UUID(uuid: байты)
    }
}

// MARK: - Покупки

/// StoreKit 2: товары, покупка, слушатель транзакций, передача чека сайту, восстановление.
@MainActor
final class ПокупкиApple: ObservableObject {
    static let shared = ПокупкиApple()

    enum Итог: Equatable {
        /// Сайт подтвердил, услуга включена, транзакция закрыта.
        case куплено
        /// Оплачено, но сайт не ответил ok — транзакция открыта, повтор при следующем запуске.
        case отложено
        /// «Попросить купить» или SCA: ждёт одобрения, придёт через Transaction.updates.
        case ждётОдобрения
        case отменено
        /// Покупки без входа нет: токен выводится из id аккаунта.
        case нуженВход
        case ошибка(String)
    }

    /// Товары App Store по product id (после Product.products).
    @Published private(set) var товары: [String: Product] = [:]
    /// Product.products хоть раз ответил (или упал).
    @Published private(set) var загружено = false
    /// App Store не ответил на запрос товаров.
    @Published private(set) var магазинНедоступен = false
    /// product id, который сейчас покупается.
    @Published private(set) var покупается: String? = nil
    @Published private(set) var восстанавливаем = false
    /// Есть оплаченные транзакции, которые сайт ещё не принял.
    @Published private(set) var естьОтложенные = false

    private var слушатель: Task<Void, Never>? = nil
    private var подпискаНаВход: AnyCancellable? = nil
    /// Транзакции, которые прямо сейчас уходят на сайт: одну и ту же не шлём дважды параллельно.
    private var отправляются: Set<UInt64> = []

    private let ключЦелей = "klikoAppleIAPTargets"
    private let ключНамерений = "klikoAppleIAPIntents"

    private init() {}

    private func т(_ ключ: String) -> String { ПокупкиAppleText.т(ключ) }

    // MARK: Запуск

    /**
     С запуска приложения (AppDelegate): слушатель Transaction.updates, повтор незакрытых через несколько секунд (страница
     сайта под слоем к тому времени загружена) и при каждом входе в аккаунт. Выключен рубильник — ничего.
     */
    func запустить() {
        guard Config.цифровыеПокупки, слушатель == nil else { return }
        слушатель = Task.detached(priority: .background) { [weak self] in
            for await результат in Transaction.updates {
                guard let self else { return }
                await self.принять(результат)
            }
        }
        подпискаНаВход = СессияПриложения.shared.$вошёл
            .removeDuplicates()
            .sink { вошёл in
                guard вошёл == true else { return }
                Task { @MainActor in
                    await ПокупкиApple.shared.повторитьОтложенные()
                }
            }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await ПокупкиApple.shared.повторитьОтложенные()
        }
    }

    // MARK: Товары

    /// Product.products(for:) по всему каталогу и дополнительным id (тарифы слотов сайта).
    func загрузитьТовары(дополнительно: [String] = []) async {
        guard Config.цифровыеПокупки else { return }
        var ids = Set(ПродуктыApple.все.map { $0.id })
        for id in дополнительно { ids.insert(id) }
        let нужно = ids.filter { товары[$0] == nil }
        if нужно.isEmpty {
            загружено = true
            return
        }
        do {
            let список = try await Product.products(for: Array(нужно))
            var словарь = товары
            for продукт in список { словарь[продукт.id] = продукт }
            товары = словарь
            магазинНедоступен = false
        } catch {
            магазинНедоступен = true
        }
        загружено = true
    }

    // MARK: Покупка

    /// Купить товар; цель — id объявления (продвижение) или резюме (топРезюме).
    func купить(_ товар: ТоварApple, цель: String?) async -> Итог {
        guard Config.цифровыеПокупки else { return .ошибка(БизнесText.т("no_digital")) }
        guard покупается == nil else { return .отменено }
        let объект = (цель ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if товар.вид.нуженОбъект && объект.isEmpty { return .ошибка(т("pick_listing_first")) }

        var uid = СессияПриложения.shared.id
        if uid.isEmpty, let с = try? await КабинетСайта.состояние(), с.вошёл == true {
            uid = с.uid
        }
        guard !uid.isEmpty, let токен = ПродуктыApple.токен(для: uid) else { return .нуженВход }

        if товары[товар.id] == nil { await загрузитьТовары(дополнительно: [товар.id]) }
        guard let продукт = товары[товар.id] else {
            return .ошибка(магазинНедоступен ? т("store_unavailable") : т("not_in_store"))
        }

        покупается = товар.id
        defer { покупается = nil }
        запомнитьНамерение(товар.id, цель: объект)
        do {
            let итог = try await продукт.purchase(options: [.appAccountToken(токен)])
            switch итог {
            case .success(let проверка):
                guard case .verified(let транзакция) = проверка else { return .ошибка(т("unverified")) }
                запомнитьЦель(транзакция.id, цель: объект)
                let принято = await отправить(транзакция, jws: проверка.jwsRepresentation)
                if принято { return .куплено }
                естьОтложенные = true
                return .отложено
            case .pending:
                return .ждётОдобрения
            case .userCancelled:
                return .отменено
            @unknown default:
                return .отменено
            }
        } catch let сбой as StoreKitError {
            switch сбой {
            case .userCancelled: return .отменено
            case .networkError: return .ошибка(т("store_unavailable"))
            case .notAvailableInStorefront: return .ошибка(т("not_in_store"))
            default: return .ошибка(т("store_error"))
            }
        } catch Product.PurchaseError.purchaseNotAllowed {
            return .ошибка(т("not_allowed"))
        } catch {
            return .ошибка(т("store_error"))
        }
    }

    // MARK: Транзакции со стороны

    /// Transaction.updates: одобренная «Попросить купить», продление PRO, покупка с другого устройства, возврат.
    func принять(_ результат: VerificationResult<Transaction>) async {
        // Неподтверждённую подпись не отдаём и не закрываем: пусть лежит у Apple, сервер её всё равно бы отверг.
        guard case .verified(let транзакция) = результат else { return }
        let принято = await отправить(транзакция, jws: результат.jwsRepresentation)
        if !принято { естьОтложенные = true }
    }

    /// Все незакрытые транзакции — на сайт ещё раз. Возвращает, сколько сайт так и не принял.
    @discardableResult
    func повторитьОтложенные() async -> Int {
        guard Config.цифровыеПокупки else { return 0 }
        var осталось = 0
        for await результат in Transaction.unfinished {
            guard case .verified(let транзакция) = результат else { continue }
            let принято = await отправить(транзакция, jws: результат.jwsRepresentation)
            if !принято { осталось += 1 }
        }
        естьОтложенные = осталось > 0
        return осталось
    }

    // MARK: Восстановление

    /// «Восстановить покупки»: AppStore.sync(), действующие права (PRO) и незакрытые — на сайт. Текст итога.
    func восстановить() async -> String {
        guard Config.цифровыеПокупки else { return БизнесText.т("no_digital") }
        восстанавливаем = true
        defer { восстанавливаем = false }
        do {
            try await AppStore.sync()
        } catch {
            return т("restore_fail")
        }
        var осталось = 0
        for await результат in Transaction.currentEntitlements {
            guard case .verified(let транзакция) = результат else { continue }
            let принято = await отправить(транзакция, jws: результат.jwsRepresentation)
            if !принято { осталось += 1 }
        }
        осталось += await повторитьОтложенные()
        естьОтложенные = осталось > 0
        if осталось > 0 { return т("restore_pending").replacingOccurrences(of: "{n}", with: String(осталось)) }
        return т("restore_done")
    }

    // MARK: Сайт

    /**
     POST /api/apple_iap.php {csrf, jws, product, service, key, target_id, transaction_id, original_transaction_id,
     app_account_token} через КабинетСайта.вызвать (МоиОбъявленияAPI.отправить кладёт csrf и один раз обновляет его на
     ответ «csrf»). Сайт идемпотентен по transaction_id, поэтому повтор после обрыва безопасен — в отличие от денежных
     запросов кошелька, которые приложение не повторяет никогда.
     ok или finish — закрыть транзакцию (finish — сайт сам решил, что чек закрыть можно: возврат уже учтён, чужой bundle);
     всё прочее, включая обрыв и «auth», — оставить открытой до следующего раза.
     */
    private func отправить(_ транзакция: Transaction, jws: String) async -> Bool {
        let номер = транзакция.id
        guard !отправляются.contains(номер) else { return false }
        отправляются.insert(номер)
        defer { отправляются.remove(номер) }

        let товар = ПродуктыApple.товар(транзакция.productID)
        let цель = цельПокупки(номер, продукт: транзакция.productID)
        let тело: [String: Any] = [
            "jws": jws,
            "product": транзакция.productID,
            "service": товар?.вид.rawValue ?? "",
            "key": товар?.ключ ?? "",
            "target_id": цель,
            "transaction_id": String(номер),
            "original_transaction_id": String(транзакция.originalID),
            "app_account_token": транзакция.appAccountToken?.uuidString.lowercased() ?? "",
        ]
        typealias A = МоиОбъявленияAPI
        guard let j = try? await A.отправить(ПродуктыApple.адресСервера, тело: тело, отКорня: true) else {
            return false
        }
        guard A.да(j["ok"]) || A.да(j["finish"]) else { return false }
        await транзакция.finish()
        забыть(номер, продукт: транзакция.productID)
        return true
    }

    // MARK: Чему покупка — на телефоне до ответа сайта

    private func словарь(_ ключ: String) -> [String: String] {
        (UserDefaults.standard.dictionary(forKey: ключ) as? [String: String]) ?? [:]
    }

    private func запомнитьНамерение(_ продукт: String, цель: String) {
        var н = словарь(ключНамерений)
        н[продукт] = цель
        UserDefaults.standard.set(н, forKey: ключНамерений)
    }

    private func запомнитьЦель(_ номер: UInt64, цель: String) {
        var ц = словарь(ключЦелей)
        ц[String(номер)] = цель
        UserDefaults.standard.set(ц, forKey: ключЦелей)
    }

    /// Цель транзакции: запомненная по её номеру, иначе последняя по этому товару (одобренная позже «Попросить купить»).
    private func цельПокупки(_ номер: UInt64, продукт: String) -> String {
        if let ц = словарь(ключЦелей)[String(номер)] { return ц }
        let цель = словарь(ключНамерений)[продукт] ?? ""
        запомнитьЦель(номер, цель: цель)
        return цель
    }

    private func забыть(_ номер: UInt64, продукт: String) {
        var ц = словарь(ключЦелей)
        let цель = ц.removeValue(forKey: String(номер))
        UserDefaults.standard.set(ц, forKey: ключЦелей)
        var н = словарь(ключНамерений)
        if let цель, н[продукт] == цель {
            н.removeValue(forKey: продукт)
            UserDefaults.standard.set(н, forKey: ключНамерений)
        }
    }
}
