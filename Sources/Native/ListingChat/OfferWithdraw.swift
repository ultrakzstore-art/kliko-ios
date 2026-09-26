import Foundation
import SwiftUI
import UIKit

/**
 «ОТОЗВАТЬ ПРЕДЛОЖЕНИЕ» — ТОРГ ПОКУПАТЕЛЯ (TestFlight, владелец 26.09.2026: «отозвать предложение нет, так же кнопка»).

 Сайт даёт покупателю забрать своё предложение цены в трёх местах, одним запросом и одним окном подтверждения:
   · карточка «Ваше предложение» в чате объявления (mkOfferOwnCard → mkOfferWithdraw, 27-marketplace):
     POST chat.php?action=offer_withdraw {csrf: _MKP_CSRF, pid};
   · карточка своего предложения в переписке кабинета (_dmOfferCard → dmOfferWithdraw → _dmOfferGo, CAB @1249978):
     POST chat.php?action=offer_withdraw {csrf: CSRF, chat_id: _dmTid}, затем dmPollTick;
   · плашка «Торг» виджета активных сделок (KLK_ADP, ×): {csrf, chat_id: cid, pid: product_id}.
 Окно — mkConfirm / boostConfirm: «Отозвать предложение?» / «Продавец больше не сможет его принять. Если деньги были
 отложены — вернутся на счёт.» / «Да, отозвать» (danger). Ответ: ok, refunded → «Предложение отозвано, деньги вернулись на
 счёт» или «Предложение отозвано»; иначе ulxErr, запасной «Не удалось отозвать»; обрыв — «Нет связи». Сервер сам кладёт в
 переписку уведомление «Покупатель отозвал своё предложение.» и ставит offer.withdrawn — карточка гаснет («Отозвано»).

 Здесь запрос один на все места: chat_id и pid, какие известны (сервер понимает любой из двух, карта кабинета §13),
 токен страницы кабинета (ИнбоксAPI.отправить — как offer_accept лид-чата; на «csrf» — свежая страница и один повтор:
 первая попытка отвергнута до записи). Путь — /kz/<язык>/chat.php, как у кабинета.

 🔴 ДЕНЬГИ. Отзыв предложения, которое подкреплено деньгами (offer.funded > 0), возвращает их на счёт — это движение
 денег, и оно, как offer_decline лид-чата, только за Config.деньгиСделок. Выключен — кнопка та же, но ведёт на
 объявление сайта с открытым чатом (?item=<номер>&chat=1), где сайт отзовёт сам. Неподкреплённое предложение денег не
 держит — отзывается здесь.

 ТоргПредложений — что приложение знает о своих ждущих предложениях в этом сеансе (из чата объявления и переписки): по
 нему страница объявления показывает полосу «Ваше предложение · N ₸» с той же кнопкой. Только память; выход стирает
 (ИнбоксМодель.стереть).
 */

// MARK: - Тексты

/// Слова сайта (i18n-marketplace-ru: of_withdraw, of_wd_*; KLK_ADP.L: wd.fail, of_wait) на kk/ru/en/ar.
enum ТекстыОтзываПредложения {
    static func т(_ ключ: String) -> String {
        let словарь = тексты[ListingChatText.язык] ?? тексты["ru"] ?? [:]
        return словарь[ключ] ?? тексты["ru"]?[ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": [
            "withdraw": "Отозвать предложение", "ask_t": "Отозвать предложение?",
            "ask_m": "Продавец больше не сможет его принять. Если деньги были отложены — вернутся на счёт.",
            "ask_ok": "Да, отозвать", "cancel": "Отмена", "ok1": "Предложение отозвано",
            "ok2": "Предложение отозвано, деньги вернулись на счёт", "fail": "Не удалось отозвать",
            "no_conn": "Нет связи", "mine": "Ваше предложение", "wait": "Ждём ответа продавца",
            "held": "Подкреплено", "on_site": "Предложение подкреплено деньгами — отозвать его можно на сайте"
        ],
        "kk": [
            "withdraw": "Ұсынысты қайтарып алу", "ask_t": "Ұсынысты қайтарып аласыз ба?",
            "ask_m": "Сатушы оны енді қабылдай алмайды. Ақша бөлінген болса — шотқа қайтады.",
            "ask_ok": "Иә, қайтарып алу", "cancel": "Бас тарту", "ok1": "Ұсыныс қайтарылды",
            "ok2": "Ұсыныс қайтарылды, ақша шотқа қайтты", "fail": "Қайтарып алу мүмкін болмады",
            "no_conn": "Байланыс жоқ", "mine": "Сіздің ұсынысыңыз", "wait": "Сатушының жауабын күтудеміз",
            "held": "Ақшамен бекітілген", "on_site": "Ұсыныс ақшамен бекітілген — оны сайтта қайтарып алуға болады"
        ],
        "en": [
            "withdraw": "Withdraw offer", "ask_t": "Withdraw the offer?",
            "ask_m": "The seller will no longer be able to accept it. If money was set aside, it returns to your account.",
            "ask_ok": "Yes, withdraw", "cancel": "Cancel", "ok1": "Offer withdrawn",
            "ok2": "Offer withdrawn, the money is back in your account", "fail": "Couldn't withdraw",
            "no_conn": "No connection", "mine": "Your offer", "wait": "Waiting for the seller",
            "held": "Backed", "on_site": "The offer is backed with money — you can withdraw it on the website"
        ],
        "ar": [
            "withdraw": "سحب العرض", "ask_t": "سحب العرض؟",
            "ask_m": "لن يتمكن البائع من قبوله بعد الآن. إذا كان المال محجوزًا فسيعود إلى حسابك.",
            "ask_ok": "نعم، اسحب", "cancel": "إلغاء", "ok1": "تم سحب العرض",
            "ok2": "تم سحب العرض وعاد المال إلى حسابك", "fail": "تعذّر سحب العرض",
            "no_conn": "لا يوجد اتصال", "mine": "عرضك", "wait": "بانتظار رد البائع",
            "held": "مدعوم بالمال", "on_site": "العرض مدعوم بالمال — يمكنك سحبه على الموقع"
        ]
    ]
}

// MARK: - Запрос

@MainActor
enum ОтзывПредложенияAPI {
    enum Итог: Equatable {
        /// Текст плашки: «Предложение отозвано» или «…, деньги вернулись на счёт».
        case готово(String)
        case ошибка(String)
    }

    private typealias З = МоиОбъявленияAPI

    /// POST chat.php?action=offer_withdraw {csrf, chat_id?, pid?} — только по нажатию, после окна подтверждения.
    static func отозвать(чат: String, объявление: String) async -> Итог {
        var тело: [String: Any] = [:]
        if !чат.isEmpty { тело["chat_id"] = чат }
        if !объявление.isEmpty { тело["pid"] = объявление }
        guard !тело.isEmpty else { return .ошибка(ТекстыОтзываПредложения.т("fail")) }
        do {
            let j = try await ИнбоксAPI.отправить("chat.php?action=offer_withdraw", тело: тело)
            if З.да(j["ok"]) {
                return .готово(ТекстыОтзываПредложения.т(З.да(j["refunded"]) ? "ok2" : "ok1"))
            }
            return .ошибка(ИнбоксAPI.текстОшибки(j, запасной: ТекстыОтзываПредложения.т("fail")))
        } catch {
            if let сбой = error as? КабинетСайта.Сбой, сбой == .сеть {
                return .ошибка(ТекстыОтзываПредложения.т("no_conn"))
            }
            return .ошибка(ТекстыОтзываПредложения.т("fail"))
        }
    }

    /// Отозвать можно здесь: предложение не держит денег, или деньги сделок включены (см. шапку).
    static func здесь(подкреплено: Int) -> Bool {
        подкреплено <= 0 || Config.деньгиСделок
    }

    /// Объявление сайта с открытым чатом (?item=<номер>&chat=1) — туда ведёт подкреплённое предложение.
    static func чатНаСайте(объявление: String) -> URL? {
        guard !объявление.isEmpty,
              let основа = Listing(номер: объявление).адрес,
              var части = URLComponents(url: основа, resolvingAgainstBaseURL: false) else { return nil }
        var поля = части.queryItems ?? []
        поля.append(URLQueryItem(name: "chat", value: "1"))
        части.queryItems = поля
        return части.url
    }
}

// MARK: - Ждущие предложения этого сеанса

/// Своё предложение, которое ещё ждёт ответа продавца: не отозвано, не заменено, не принято.
struct ЖдущееПредложениеЦены: Equatable {
    let объявление: String
    /// chat_id чата объявления или tid переписки — что знает место, где предложение видно.
    let чат: String
    let цена: Int
    let подкреплено: Int
}

@MainActor
final class ТоргПредложений: ObservableObject {
    static let shared = ТоргПредложений()

    /// Номер объявления → ждущее предложение.
    @Published private(set) var ждущие: [String: ЖдущееПредложениеЦены] = [:]
    /// Объявления, по которым запрос уже идёт: второе нажатие ждёт первого ответа.
    @Published private(set) var занято: Set<String> = []
    /// Итог последнего отзыва по объявлению — строка на месте полосы (2,6 с, как toast сайта).
    @Published private(set) var итоги: [String: String] = [:]

    /// Растёт при выходе: ответ, пришедший после, не применяется.
    private var поколение = 0

    private init() {}

    /// Место, где видно переписку, сообщило, что ждёт (или что ждущего больше нет — nil).
    func запомнить(объявление: String, _ ждущее: ЖдущееПредложениеЦены?) {
        guard !объявление.isEmpty else { return }
        if ждущие[объявление] != ждущее { ждущие[объявление] = ждущее }
    }

    /**
     Отозвать (окно подтверждения уже показано). nil — запрос по этому объявлению уже идёт. Готово — ждущего больше нет,
     переписки перечитывают себя сами, список «Чата» перечитывается (уведомление сервера станет превью строки).
     */
    func отозвать(объявление: String, чат: String, сОбъявлением: Bool = true) async -> ОтзывПредложенияAPI.Итог? {
        let ключ = Self.ключ(объявление: объявление, чат: чат)
        guard !ключ.isEmpty, !занято.contains(ключ) else { return nil }
        занято.insert(ключ)
        defer { занято.remove(ключ) }
        let моё = поколение
        /* Переписка кабинета шлёт только chat_id (_dmOfferGo), чат объявления и плашка «Торг» — ещё и pid. */
        let итог = await ОтзывПредложенияAPI.отозвать(чат: чат, объявление: сОбъявлением ? объявление : "")
        guard моё == поколение else { return nil }
        switch итог {
        case .готово(let текст):
            ОткликСайта.успех()
            if !объявление.isEmpty { ждущие[объявление] = nil }
            показать(текст, объявление: объявление)
            ИнбоксМодель.shared.перепискаЗакрыта()
        case .ошибка(let текст):
            ОткликСайта.предупреждение()
            показать(текст, объявление: объявление)
        }
        UIAccessibility.post(notification: .announcement, argument: {
            switch итог {
            case .готово(let т), .ошибка(let т): return т
            }
        }())
        return итог
    }

    /// Запрос по этому предложению уже идёт.
    func идёт(объявление: String, чат: String) -> Bool {
        занято.contains(Self.ключ(объявление: объявление, чат: чат))
    }

    private static func ключ(объявление: String, чат: String) -> String {
        объявление.isEmpty ? чат : объявление
    }

    private func показать(_ текст: String, объявление: String) {
        guard !объявление.isEmpty else { return }
        withAnimation(ДвижениеСайта.появление) { итоги[объявление] = текст }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard let self, self.итоги[объявление] == текст else { return }
            withAnimation(ДвижениеСайта.уход) { self.итоги[объявление] = nil }
        }
    }

    func стереть() {
        поколение += 1
        ждущие = [:]
        занято = []
        итоги = [:]
    }
}

// MARK: - Окно подтверждения

extension View {
    /// mkConfirm сайта для отзыва: «Отозвать предложение?», пояснение, «Да, отозвать» (danger) и «Отмена».
    func вопросОтозватьПредложение(_ показан: Binding<Bool>, отозвать: @escaping () -> Void) -> some View {
        confirmationDialog(ТекстыОтзываПредложения.т("ask_t"), isPresented: показан, titleVisibility: .visible) {
            Button(ТекстыОтзываПредложения.т("ask_ok"), role: .destructive, action: отозвать)
            Button(ТекстыОтзываПредложения.т("cancel"), role: .cancel) {}
        } message: {
            Text(ТекстыОтзываПредложения.т("ask_m"))
        }
    }
}

// MARK: - Кнопка (.mk-ofc-x сайта)

/// «Отозвать предложение» под карточкой: во всю ширину, мелко, серым с подчёркиванием, как .mk-ofc-x; пока идёт запрос —
/// колесо вместо текста.
struct КнопкаОтозватьПредложение: View {
    let занято: Bool
    let нажать: () -> Void

    var body: some View {
        Button(action: нажать) {
            ZStack {
                if занято {
                    SiteSpinner.мелкий
                } else {
                    Text(ТекстыОтзываПредложения.т("withdraw"))
                        .font(.system(size: 13, weight: .semibold))
                        .underline()
                        .foregroundStyle(Theme.текстВторой)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
        .disabled(занято)
        .padding(.top, 6)
        .accessibilityLabel(ТекстыОтзываПредложения.т("withdraw"))
    }
}

// MARK: - Полоса на странице объявления

/**
 Страница объявления: своё ждущее предложение, известное в этом сеансе, — строка над панелью связи: «Ваше предложение ·
 N ₸», «Ждём ответа продавца» (или «Подкреплено · N ₸») и «Отозвать предложение». После ответа — строка итога на 2,6 с.
 Светлая и тёмная — краски Theme.
 */
struct ПолосаСвоегоПредложения: View {
    let объявление: String
    let открыть: (URL) -> Void
    @ObservedObject private var торг = ТоргПредложений.shared
    @State private var спросить = false

    init(объявление: String, открыть: @escaping (URL) -> Void) {
        self.объявление = объявление
        self.открыть = открыть
    }

    var body: some View {
        Group {
            if let итог = торг.итоги[объявление] {
                Text(итог)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.текст)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                    .transition(.opacity)
            } else if let ждущее = торг.ждущие[объявление] {
                полоса(ждущее)
                    .transition(.opacity)
            }
        }
        .animation(ДвижениеСайта.смена, value: торг.ждущие[объявление])
        .animation(ДвижениеСайта.смена, value: торг.итоги[объявление])
        .вопросОтозватьПредложение($спросить) {
            guard let ждущее = торг.ждущие[объявление] else { return }
            Task { _ = await торг.отозвать(объявление: ждущее.объявление, чат: ждущее.чат) }
        }
    }

    private func полоса(_ ждущее: ЖдущееПредложениеЦены) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "tag")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.акцент)
                .frame(width: 32, height: 32)
                .background(Theme.оттенокАкцента, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(ТекстыОтзываПредложения.т("mine") + " · " + ListingCard.тенге(Double(ждущее.цена)))
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(ждущее.подкреплено > 0
                     ? ТекстыОтзываПредложения.т("held") + " · " + ListingCard.тенге(Double(ждущее.подкреплено))
                     : ТекстыОтзываПредложения.т("wait"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Button {
                нажать(ждущее)
            } label: {
                ZStack {
                    if торг.идёт(объявление: ждущее.объявление, чат: ждущее.чат) {
                        SiteSpinner.мелкий
                    } else {
                        Text(ТекстыОтзываПредложения.т("withdraw"))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.текст)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 10)
                .frame(minWidth: 44, minHeight: 36)
                .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                        .strokeBorder(Theme.линия, lineWidth: 1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
            .disabled(торг.идёт(объявление: ждущее.объявление, чат: ждущее.чат))
            .accessibilityHint(ОтзывПредложенияAPI.здесь(подкреплено: ждущее.подкреплено)
                               ? "" : ListingPageText.т("on_site"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
    }

    private func нажать(_ ждущее: ЖдущееПредложениеЦены) {
        if ОтзывПредложенияAPI.здесь(подкреплено: ждущее.подкреплено) {
            спросить = true
        } else if let адрес = ОтзывПредложенияAPI.чатНаСайте(объявление: ждущее.объявление) {
            открыть(адрес)
        }
    }
}
