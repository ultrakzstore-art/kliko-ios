import SwiftUI

/**
 «ЧЕЙ ХОД» СДЕЛКИ (ultra-site 13.10.2026: «Сделки: шаги после оплаты — чей ход, четыре шага, срок проверки, деньги у Kliko»).

 Сервер отдаёт deal.next в escrow.php?action=deal и у каждой сделки my_deals: null или {who, key, left, lead, text}.
   · who — me (ход смотрящего), peer (ждём вторую сторону), wait (ждём курьера или перевозчика);
   · key — ключ словаря сайта dnx_…; left — секунд до срока, после которого что-то случится само (0 — срока нет);
   · lead и text — готовые слова на языке зрителя.
 null — услуга, аренда, задаток, возврат, старые схемы с кодами: остаются прежние подписи. Старый ответ без поля — то же.

 Здесь: разбор (ХодСделки), обратный отсчёт раз в минуту (ОтсчётХодаСделки), метка «Ваш ход», слот строки списка
 «Мои сделки» (СлотХодаСделки) и блок в карточке сделки (БлокХодаСделки).
 */
struct ХодСделки: Equatable {
    /// me / peer / wait.
    let кто: String
    /// Ключ словаря сайта (dnx_…) — для разбора, на экран не идёт.
    let ключ: String
    /// next.lead — коротко, что сейчас.
    let заголовок: String
    /// next.text — что сделать или чего ждём.
    let текст: String
    /// Когда что-то случится само: сейчас + left. nil — срока нет (left 0) или на экране копия без сети.
    var срок: Date?

    init?(_ з: Any?) {
        guard let d = з as? [String: Any] else { return nil }
        typealias A = СделкиAPI
        let lead = A.строка(d["lead"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let text = A.строка(d["text"]).trimmingCharacters(in: .whitespacesAndNewlines)
        /* Нет слов — показывать нечего: прежние подписи (api/active_deals.php отдаёт next без lead и text). */
        guard !lead.isEmpty || !text.isEmpty else { return nil }
        кто = A.строка(d["who"]).trimmingCharacters(in: .whitespaces).lowercased()
        ключ = A.строка(d["key"])
        заголовок = lead
        текст = text
        let осталось = A.число(d["left"])
        /* Только конечный и разумный срок: inf или 1e999 строкой дали бы отсчёт, роняющий Int(...) в TimelineView. */
        срок = (осталось.isFinite && осталось > 0 && осталось < 400 * 86_400) ? Date().addingTimeInterval(осталось) : nil
    }

    /// who == "me": ход того, кто смотрит, — метка «Ваш ход».
    var мойХод: Bool { кто == "me" }

    /// Одной строкой без разметки — строка списка и VoiceOver.
    var строкой: String {
        let части = [ТекстСделки.чистый(заголовок), ТекстСделки.чистый(текст)].filter { !$0.isEmpty }
        return части.joined(separator: " ")
    }

    /// Краска строки списка: мой ход — жёлтая (как срочные подсказки), ждём — синяя.
    var видВСписке: ВидСтатусаСделки { мойХод ? .предупреждение : .инфо }

    /// Краска блока в карточке.
    var видВКарточке: ВидЗаметкиСделки { мойХод ? .предупреждение : .инфо }

    /// Значок, когда ход не мой: ждём вторую сторону — песочные часы, курьера или перевозчика — машина.
    var символ: String { кто == "wait" ? "box.truck" : "hourglass" }
}

extension СделкаКратко {
    /// Копия с диска: срок в ней посчитан от времени того ответа — отсчёт не показываем.
    var безСрока: СделкаКратко {
        var с = self
        с.ход?.срок = nil
        return с
    }
}

extension Сделка {
    /// Копия с диска: срок в ней посчитан от времени того ответа — отсчёт не показываем.
    var безСрока: Сделка {
        var с = self
        с.ход?.срок = nil
        return с
    }
}

// MARK: - Обратный отсчёт

enum ОтсчётСделки {
    /// «осталось 2 ч 15 мин», «осталось 1 дн 3 ч», «осталось 7 мин»; срок вышел — пусто. Минуты — вверх: «1 мин» до конца.
    static func текст(до срок: Date, сейчас: Date) -> String {
        let секунд = срок.timeIntervalSince(сейчас)
        guard секунд > 0, секунд.isFinite, let всего = Int(exactly: (секунд / 60).rounded(.up)) else { return "" }
        let т = ХодСделкиText.т
        let минут = max(1, всего)
        let дни = минут / 1440
        let часы = (минут % 1440) / 60
        let мин = минут % 60
        var части: [String] = []
        if дни > 0 { части.append(String(дни) + " " + т("d")) }
        if часы > 0 { части.append(String(часы) + " " + т("h")) }
        if дни == 0 && мин > 0 { части.append(String(мин) + " " + т("min")) }
        if части.isEmpty { части.append(String(дни) + " " + т("d")) }
        return String(format: т("left"), части.joined(separator: " "))
    }

    /**
     Опора расписания: момент в прошлом, отстоящий от срока на целое число минут. Тогда отсчёт перерисовывается ровно
     тогда, когда меняется число минут, — раз в минуту.
     */
    static func опора(_ срок: Date) -> Date {
        let шагов = max(0, (срок.timeIntervalSinceNow / 60).rounded(.up)) + 1
        return срок.addingTimeInterval(-шагов * 60)
    }
}

/// «⏰ осталось 2 ч 15 мин» — тикает раз в минуту; срок вышел — ничего (сервер пришлёт новое состояние).
struct ОтсчётХодаСделки: View {
    let срок: Date
    var мелко = false

    var body: some View {
        TimelineView(.periodic(from: ОтсчётСделки.опора(срок), by: 60)) { контекст in
            let текст = ОтсчётСделки.текст(до: срок, сейчас: контекст.date)
            if !текст.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: "alarm")
                        .font(.system(size: мелко ? 11 : 12, weight: .bold))
                        .accessibilityHidden(true)
                    Text(текст)
                        .font(.system(size: мелко ? 11 : 13, weight: .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
        }
    }
}

/// Метка «Ваш ход»: залитая капсула цветом срочного.
struct МеткаХодаСделки: View {
    var мелко = false

    var body: some View {
        Text(ХодСделкиText.т("your_move"))
            .font(.system(size: мелко ? 10 : 11, weight: .heavy))
            .lineLimit(1)
            .foregroundStyle(Theme.поверхность)
            .padding(.horizontal, мелко ? 6 : 8)
            .padding(.vertical, мелко ? 2 : 3)
            .background(КраскаСделокКабинета.предупреждениеТекст, in: Capsule())
            .fixedSize()
    }
}

// MARK: - Строка списка «Мои сделки»

/// Слот состояния строки списка, когда сервер прислал next: «Ваш ход» или значок, lead + text в одну строку, отсчёт справа.
struct СлотХодаСделки: View {
    let ход: ХодСделки

    /// Та же высота, что у прежнего слота (КарточкаВСпискеСделок): карточки списка одной высоты.
    private static let высота: CGFloat = 30

    var body: some View {
        let вид = ход.видВСписке
        HStack(spacing: 6) {
            if ход.мойХод {
                МеткаХодаСделки(мелко: true)
            } else {
                Image(systemName: ход.символ)
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityHidden(true)
            }
            строка
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let срок = ход.срок {
                ОтсчётХодаСделки(срок: срок, мелко: true)
                    .foregroundStyle(ход.мойХод ? КраскаСделокКабинета.плохоТекст : вид.текст)
                    .fixedSize()
            }
        }
        .foregroundStyle(вид.текст)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: Self.высота, alignment: .leading)
        .background(вид.фон, in: RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// lead жирным, text следом обычным.
    private var строка: Text {
        let заголовок = ТекстСделки.чистый(ход.заголовок)
        let текст = ТекстСделки.чистый(ход.текст)
        if заголовок.isEmpty {
            return Text(текст).font(.system(size: 12, weight: .semibold))
        }
        if текст.isEmpty {
            return Text(заголовок).font(.system(size: 12, weight: .bold))
        }
        return Text(заголовок).font(.system(size: 12, weight: .bold))
            + Text(" " + текст).font(.system(size: 12, weight: .regular))
    }
}

// MARK: - Карточка сделки

/// Блок «чей ход» в шаге мастера карточки: «Ваш ход», lead, text и отсчёт до срока.
struct БлокХодаСделки: View {
    let ход: ХодСделки

    var body: some View {
        let вид = ход.видВКарточке
        VStack(alignment: .leading, spacing: 6) {
            if ход.мойХод {
                МеткаХодаСделки()
            }
            if !ход.заголовок.isEmpty {
                ТекстСделки.сЖирным(ход.заголовок)
                    .font(.system(size: 15, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !ход.текст.isEmpty {
                ТекстСделки.сЖирным(ход.текст)
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let срок = ход.срок {
                ОтсчётХодаСделки(срок: срок)
                    .padding(.top, 2)
            }
        }
        .foregroundStyle(вид.краска)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(вид.фон, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                .strokeBorder(вид.кромка, lineWidth: 1.5)
        }
        .accessibilityElement(children: .combine)
    }
}
