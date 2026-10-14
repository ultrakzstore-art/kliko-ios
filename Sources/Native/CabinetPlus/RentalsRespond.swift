import SwiftUI
import UIKit

/**
 «МОИ АРЕНДЫ»: СРОК ОТВЕТА ВЛАДЕЛЬЦА, ЗАКРЫТИЕ БЕЗ ОТВЕТА, ВЕРИФИКАЦИЯ ВЛАДЕЛЬЦА И ПЕРЕХОД ИЗ ПУША (ultra-site 13.10.2026:
 «Аренда, вторая часть…» и «Аренда проще…»).

 Поля сервера (только добавления, старые ответы работают как раньше):
   · запись аренды cabinet.php?action=my_rentals — respond_by (ISO-время, у запросов requested), cancel_reason
     ("no_answer" у закрытого без ответа, статус прежний — cancelled);
   · корень ответа my_rentals — owner_bookable (принимает ли площадка заявки для этого владельца) и owner_rent_items;
   · пуш rent и rental… ведёт на /cabinet.php?go=rentals&rent=<номер> — экран аренд с этой карточкой (ФокусАренды).
 Пуш rental_noanswer ведёт на /marketplace.php?item=<номер> — его открывает общий путь адреса пуша (объявление).
 */

// MARK: - Срок ответа

enum СрокОтветаАренды {
    /// respond_by: ISO с поясом («2026-10-14T15:00:00+05:00») или «2026-10-14 15:00:00»; пусто и мусор — nil.
    static func дата(_ строка: String) -> Date? {
        СделкиФормат.дата(строка)
    }

    /// «15:00, 14.10» — ЧЧ:ММ, ДД.ММ по часам телефона.
    static func текст(_ дата: Date) -> String {
        let ф = DateFormatter()
        ф.locale = Locale(identifier: "en_US_POSIX")
        ф.calendar = Calendar(identifier: .gregorian)
        ф.timeZone = TimeZone.current
        ф.dateFormat = "HH:mm, dd.MM"
        return ф.string(from: дата)
    }
}

// MARK: - Переход к карточке аренды из пуша

/**
 Номер аренды, к которой надо привести экран «Мои аренды» (пуш rent / rental… с адресом cabinet.php?go=rentals&rent=).
 Роутер кабинета адрес с двумя параметрами своим экраном не открывает — пуш кладёт номер сюда и открывает раздел
 ?s=rentals (свой экран); экран, загрузив список, сам переключит вкладку «Сдаю» / «Арендую», прокрутит к карточке,
 подсветит её и забудет номер.
 */
@MainActor
final class ФокусАренды: ObservableObject {
    static let shared = ФокусАренды()

    /// Номер аренды, к которой вести; nil — никуда.
    @Published var номер: String? = nil

    private init() {}

    /**
     Адрес пуша аренды: /cabinet.php (или /cabinet, /kz/<язык>/cabinet.php) с go=rentals или s=rentals и, по желанию,
     rent=<номер>. Вернёт номер, пустую строку (раздел без номера) или nil — адрес не про аренды.
     */
    nonisolated static func номер(из адрес: String) -> String? {
        guard let части = URLComponents(string: адрес.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        if let хост = части.host?.lowercased(), хост != "kliko.kz" && !хост.hasSuffix(".kliko.kz") { return nil }
        guard (части.fragment ?? "").isEmpty,
              части.path.range(of: "^(/[a-z]{2}/[a-z]{2})?/cabinet(\\.php)?/?$", options: .regularExpression) != nil
        else { return nil }
        let параметры = (части.queryItems ?? []).filter { !$0.name.lowercased().hasPrefix("utm_") }
        guard Set(параметры.map { $0.name }).isSubset(of: ["go", "s", "rent"]) else { return nil }
        func знач(_ имя: String) -> String {
            (параметры.first(where: { $0.name == имя })?.value ?? "").trimmingCharacters(in: .whitespaces)
        }
        let раздел = (знач("go").isEmpty ? знач("s") : знач("go")).lowercased()
        guard раздел == "rentals" else { return nil }
        let номер = знач("rent")
        if номер.isEmpty { return "" }
        guard номер.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil else { return nil }
        return номер
    }

    /// Открыть «Мои аренды» своим экраном и запомнить карточку; своего экрана нет — адрес пуша как есть.
    static func открыть(_ номер: String, запасной: String) {
        let путь = "/cabinet.php?s=rentals"
        guard let адрес = URL(string: путь, relativeTo: Config.apiBase), NativeRouter.распознать(адрес) != nil else {
            WebBridge.shared.openPath(запасной)
            return
        }
        shared.номер = номер.isEmpty ? nil : номер
        WebBridge.shared.openPath(путь)
    }
}

// MARK: - Плашка владельцу без верификации

/// owner_bookable == false: «Пройдите верификацию, чтобы принимать заявки на аренду» и кнопка своего окна верификации.
struct ПлашкаВерификацииАренды: View {
    private func т(_ ключ: String) -> String { АрендаОтветText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(КраскаОбъявлений.предупреждениеТекст)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(т("verify_t"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.текст)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(т("verify_s"))
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            КнопкаРаздела(подпись: т("verify_go"), значок: "checkmark.shield", вид: .главная) {
                if !ОкнаПриложения.shared.показать(.верификация) { ВерификацияПоверх.показать() }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(КраскаОбъявлений.предупреждениеФон,
                    in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
    }
}

// MARK: - Строка срока и «Владелец не ответил» в карточке аренды

/**
 В карточке аренды: у запроса requested с respond_by — «Владелец ответит до 15:00, 14.10» (арендатору) или «Ответьте до…»
 (владельцу); у cancelled с cancel_reason no_answer — пояснение и «Открыть объявление» арендатору. Иначе ничего.
 */
struct БлокОтветаАренды: View {
    let аренда: АрендаКабинета

    private func т(_ ключ: String) -> String { АрендаОтветText.т(ключ) }

    var body: some View {
        if аренда.статус == "requested", let до = аренда.ответитьДо {
            Label(String(format: т(аренда.продавец ? "respond_owner" : "respond_renter"), СрокОтветаАренды.текст(до)),
                  systemImage: "clock")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(аренда.продавец ? КраскаОбъявлений.предупреждениеТекст : Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
        } else if аренда.безОтвета {
            ЗаметкаБизнеса(т(аренда.продавец ? "noanswer_owner_s" : "noanswer_s"), тон: .серый, значок: "clock.badge.xmark")
            if !аренда.продавец, годный(аренда.объявление) {
                КнопкаРаздела(подпись: т("open_item"), значок: "arrow.up.forward.square", вид: .обычная) {
                    WebBridge.shared.открытьЭкран(.объявление(id: аренда.объявление), запасной: nil)
                }
            }
        }
    }

    private func годный(_ номер: String) -> Bool {
        номер.range(of: "^[A-Za-z0-9_-]{1,40}$", options: .regularExpression) != nil
    }
}
