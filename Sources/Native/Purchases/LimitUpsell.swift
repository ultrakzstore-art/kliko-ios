import SwiftUI

/**
 «РАСШИРИТЬ» ПРЯМО В ОКНЕ ЛИМИТА (владелец 16.10.2026, скрин «Мои объявления» TestFlight 1.12 (76): «Лимиты если
 достигнуты — в окне предлагать расширить сразу»; затем «по всем моментам разом»).

 Одно правило на все окна, где человек упирается в лимит, который покупка App Store правда поднимает (правило 3.1.1 —
 только покупкой Apple, без цен в тенге, ссылок и слов об оплате на сайте):
   · слоты объявлений — тариф слотов, запасные комбо (слоты + Kliko AI) и PRO (PRO_SLOTS);
   · квота Kliko AI — пакет Kliko AI, запасные комбо (дни Kliko AI) и PRO (дни ИИ).
 Цепочка: берётся первая услуга, товар которой загружен из App Store. Ни одной — товары ещё грузятся (кнопка с колесом
 и повторный запрос App Store) или нет вовсе (кнопки нет, честный текст окна). Где лимит не продаётся (частота, суточные
 паузы, модерация, чужая квота) — кнопки нет никогда.

 Почему на скрине кнопки не было: товар слотов не загрузился, а окно App Store ещё раз не спрашивало и комбо с PRO не
 пробовало. Теперь КнопкаРасширения сама зовёт ПокупкиApple.подгрузить, а настоящие тарифы сервера (slots.tiers из
 my_items) подгружаются заранее — подгрузитьТарифыСлотов.
 */
@MainActor
enum РасширениеЛимита {
    /// Что поднимает лимит слотов объявлений.
    static let слоты: [ВидУслугиApple] = [.слоты, .комбо, .про]
    /// Что снимает лимит Kliko AI (распознавание, сборка услуги, импорт, черновик резюме, примерка, 3D).
    static let ии: [ВидУслугиApple] = [.пакетИИ, .комбо, .про]
    /**
     Примерка ИИ: только пакет Kliko AI (docs/SERVER_TRYON.md, §6). Premium «Свой ИИ» лимит тоже поднимает, но меняет
     обработчика фото (ключ человека — его поставщик), а согласие давалось на Kliko AI (5.1.2(i)); и подпись «Больше
     примерок с Kliko AI» ему не подходит (2.3). Premium — из его окна, со своим согласием.
     */
    static let примерка: [ВидУслугиApple] = [.пакетИИ]
    /// Сборка 3D: пакет Kliko AI или PRO с днями ИИ (docs/SERVER_3D.md, §10).
    static let сборка3D: [ВидУслугиApple] = [.пакетИИ, .про]

    /// Первая услуга цепочки, которую можно купить сейчас (товар загружен). nil — рубильник выключен или товара нет.
    static func вид(_ цепочка: [ВидУслугиApple]) -> ВидУслугиApple? {
        guard Config.цифровыеПокупки else { return nil }
        let покупки = ПокупкиApple.shared
        return цепочка.first(where: { допустим($0) && покупки.можноКупить($0) })
    }

    /// Товары цепочки ещё грузятся (не дольше ПокупкиApple.срокЗагрузки), а купить пока нечего.
    static func грузится(_ цепочка: [ВидУслугиApple]) -> Bool {
        guard Config.цифровыеПокупки else { return false }
        let покупки = ПокупкиApple.shared
        return цепочка.contains(where: { допустим($0) && покупки.доступ($0) == .грузится })
    }

    /// Окно даст «Расширить»: товар есть или ещё грузится.
    static func есть(_ цепочка: [ВидУслугиApple]) -> Bool {
        вид(цепочка) != nil || грузится(цепочка)
    }

    /// PRO уже оплачен (подписка или срок сайта) — второй раз он лимит не поднимет, из цепочки его прочь.
    private static func допустим(_ вид: ВидУслугиApple) -> Bool {
        guard вид == .про, let с = БизнесМодель.shared.страница else { return true }
        return !(с.proАктивен && !с.proБесплатно)
    }

    /**
     Текст сервера в окне лимита: без цены, оплаты, кошелька и «на сайте» (правило 3.1.1); такой, машинный код или
     пусто — своя фраза запасной. Длинный обрезается.
     */
    nonisolated static func текстСервера(_ строка: String, запасной: String, предел: Int = 300) -> String {
        let годный = ИИФотоAPI.текстСервера(строка, предел: предел)
        guard !годный.isEmpty else { return запасной }
        /* Сайт зовёт расширить у себя («в кабинете на сайте», «с кошелька»): в приложении это ведёт мимо App Store. */
        let словаСайта = ["сайт", "site", "website", "кошел", "wallet", "әмиян", "kliko.kz", "http", "موقع", "محفظ"]
        let строчная = годный.lowercased()
        if словаСайта.contains(where: { строчная.contains($0) }) { return запасной }
        return годный
    }

    /// Тарифы, которые уже просили у App Store: тот же список повторно не шлём.
    private static var запрошеныТарифы: Set<String> = []

    /**
     slots.tiers из my_items: товары App Store под каждый тариф сервера (kz.kliko.app.slots.<N>) — заранее, а не только
     при открытии окна покупки. Без этого можноКупить(.слоты) знает лишь числа каталога, и «Расширить» не появлялось.
     */
    static func подгрузитьТарифыСлотов(_ слоты: [String: Any]?) {
        guard Config.цифровыеПокупки, let слоты else { return }
        typealias A = МоиОбъявленияAPI
        let сырые: [Any] = (слоты["tiers"] as? [Any]) ?? []
        var ids: [String] = []
        for запись in сырые {
            guard let тариф = запись as? [String: Any] else { continue }
            let число = A.целое(тариф["slots"])
            guard число > 0, A.целое(тариф["price"]) > 0 else { continue }
            let id = ПродуктыApple.товарСлотов(число).id
            if !запрошеныТарифы.contains(id) { ids.append(id) }
        }
        guard !ids.isEmpty else { return }
        for id in ids { запрошеныТарифы.insert(id) }
        Task { @MainActor in
            let покупки = ПокупкиApple.shared
            await покупки.загрузитьТовары(дополнительно: ids)
            /* App Store не ответил (сеть, срок) — эти тарифы спросить снова при следующем my_items, а не ждать
               перезапуска. Ответил, но товара нет (не заведён) — не дёргаем его каждый раз. */
            guard покупки.магазинНедоступен else { return }
            for id in ids where покупки.товары[id] == nil { запрошеныТарифы.remove(id) }
        }
    }

    /// Ответ сервера: квота Kliko AI кончилась (need_paid в любом из мест, где его кладут recognize, ai_service,
    /// импорт и черновик резюме).
    nonisolated static func квотаИИ(_ j: [String: Any]) -> Bool {
        typealias A = МоиОбъявленияAPI
        return A.да(j["need_paid"]) || A.строка(j["ai_reason"]) == "need_paid" || A.строка(j["error"]) == "need_paid"
    }

    /// Уведомление .klikoУслугаAppleВключена — про услугу из этой цепочки (её покупка подняла этот лимит).
    nonisolated static func подняло(_ уведомление: Notification, _ цепочка: [ВидУслугиApple]) -> Bool {
        let услуга = (уведомление.userInfo?["service"] as? String) ?? ""
        return цепочка.contains(where: { $0.rawValue == услуга })
    }
}

/**
 Кнопка «Расширить» по единому правилу (ДоступПокупкиApple), в стиле окна, где стоит: товар цепочки загружен — кнопка;
 грузится — та же кнопка с колесом, не нажимается; нет — ничего. Пока товара нет, ещё раз спрашивает App Store (не чаще
 раза в минуту). Нажатие отдаёт услугу, которую открыть: ЛистУслугиApple.показать(вид, готово: …).
 */
struct КнопкаРасширения<Кнопка: View>: View {
    let цепочка: [ВидУслугиApple]
    let действие: (ВидУслугиApple) -> Void
    /// Вид кнопки окна: занято — показать колесо; нажать — что делать по нажатию.
    let кнопка: (_ занято: Bool, _ нажать: @escaping () -> Void) -> Кнопка
    @ObservedObject private var покупки = ПокупкиApple.shared

    init(цепочка: [ВидУслугиApple], действие: @escaping (ВидУслугиApple) -> Void,
         @ViewBuilder кнопка: @escaping (_ занято: Bool, _ нажать: @escaping () -> Void) -> Кнопка) {
        self.цепочка = цепочка
        self.действие = действие
        self.кнопка = кнопка
    }

    var body: some View {
        if let вид = РасширениеЛимита.вид(цепочка) {
            кнопка(false, { действие(вид) })
        } else if РасширениеЛимита.грузится(цепочка) {
            кнопка(true, {})
                .disabled(true)
                .task { await ПокупкиApple.shared.подгрузить() }
        } else {
            Color.clear
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
                .task { await ПокупкиApple.shared.подгрузить() }
        }
    }
}

extension КнопкаРасширения where Кнопка == КнопкаПокупкиApple {
    /// Зелёная кнопка окна покупки (.club-btn.pri) — там, где у окна своей главной кнопки нет.
    init(цепочка: [ВидУслугиApple], подпись: String, значок: String = "square.stack.3d.up",
         действие: @escaping (ВидУслугиApple) -> Void) {
        self.init(цепочка: цепочка, действие: действие) { занято, нажать in
            КнопкаПокупкиApple(подпись: подпись, значок: значок, занято: занято, действие: нажать)
        }
    }
}

/**
 Чип «Расширить» карточки «Доступно» в «Моих объявлениях»: мятная капсула; главная — залита зелёным (лимит достигнут,
 это главное действие карточки); грузится — колесо, не нажимается.
 */
struct ЧипРасширения: View {
    let подпись: String
    var главная = false
    var грузится = false
    let действие: () -> Void

    var body: some View {
        Button(action: действие) {
            HStack(spacing: 5) {
                if грузится {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(главная ? Color.white : Theme.акцент)
                }
                Text(подпись)
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)
            }
            .foregroundStyle(главная ? Color.white : Theme.акцент)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(главная ? Theme.зелёный : Theme.оттенокАкцента, in: Capsule())
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.95))
        .disabled(грузится)
        .animation(ДвижениеСайта.появление, value: главная)
    }
}

/// Зелёная главная кнопка окна лимита с колесом «грузится»: значок, подпись, Theme.зелёный, высота 46.
struct ГлавнаяКнопкаЛимита: View {
    let подпись: String
    var значок: String = "square.stack.3d.up"
    var занято = false
    let действие: () -> Void

    var body: some View {
        Button(action: действие) {
            HStack(spacing: 8) {
                if занято {
                    ProgressView()
                        .tint(Color.white)
                } else {
                    Image(systemName: значок)
                        .font(.system(size: 15, weight: .semibold))
                        .accessibilityHidden(true)
                }
                Text(подпись)
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 46)
            .padding(.horizontal, 12)
            .background(Theme.зелёный, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
        .disabled(занято)
    }
}
