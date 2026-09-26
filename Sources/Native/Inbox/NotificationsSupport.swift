import SwiftUI
import UIKit

/**
 КОЛОКОЛЬЧИК И ПОДДЕРЖКА — ЭТАП 45 (владелец 26.09.2026: «всё одно и то же, просто код разный»;
 Config.нативныеСообщенияКабинета).

 КОЛОКОЛЬЧИК (карта §6.3.1–6.3.2). JSON-списка уведомлений у сайта нет: до 15 записей сервер печатает прямо в страницу
 кабинета (#notif-panel, <div class="notif-item nt-… [nu]">, .n-txt, .n-when, .n-rep «×N», onclick). Поэтому список
 разбирается из той же страницы кабинета, которую вкладка «Кабинет» читает всё равно (КабинетСайта.страницаКабинета).
 Переходы из onclick — два вида, оба виденных в снимке: openDeal('KLK-…') — карточка сделки; ulx_open_chat {pid} —
 чат объявления (у приложения — чат объявления этапа 38). Открыл колокольчик — POST cabinet.php?action=mark_notif_read
 {csrf}, как toggleNotifications → markAllRead сайта (ответ сайт не читает). Настроек уведомлений по типам у сайта нет.

 ПОДДЕРЖКА (карта §6.8). Переписка по обращению — ссылка cabinet.php?ticket=<id>: GET sup_my_get&id= → ticket{id, status,
 topic_lbl, messages[{from, text, at}]}, ответ — POST sup_my_reply {csrf, id, text} → ticket. Списка «моих обращений» у
 кабинета нет. «Запросить данные у поддержки» (корзина «Чата») — POST support.php?action=create {topic: "data", text
 (от 10 знаков), ref: "", website: "", ft: 9999} без токена, как dataReqSend. «Справочный центр» — страница HELP_URL.
 */

// MARK: - Колокольчик

/// Запись .notif-item.
struct УведомлениеКабинета: Identifiable, Equatable {
    let id: Int
    /// nt-ok | nt-warn | nt-lead | nt-bc | nt-exch.
    let вид: String
    /// .nu — непрочитанное (после открытия колокольчика гаснет и на телефоне).
    var новое: Bool
    let текст: String
    let когда: String
    /// .n-rep — «×5»: одинаковые события свёрнуты.
    let повторов: String
    /// openDeal('…') в onclick.
    let сделка: String?
    /// ulx_open_chat {pid:'…'} в onclick.
    let товар: String?
}

enum УведомленияКабинета {
    /// Записи панели #notif-panel страницы кабинета — в порядке сервера.
    static func разобрать(_ html: String) -> [УведомлениеКабинета] {
        guard let начало = html.range(of: "id=\"notif-panel\"") else { return [] }
        var хвост = html[начало.upperBound...]
        if let конец = хвост.range(of: "/.notif-body") { хвост = хвост[..<конец.lowerBound] }
        let панель = String(хвост)
        let куски = панель.components(separatedBy: "<div class=\"notif-item")
        var список: [УведомлениеКабинета] = []
        for (i, кусок) in куски.enumerated() where i > 0 {
            let классы = String(кусок.prefix(while: { $0 != "\"" }))
            let набор = Set(классы.split(separator: " ").map(String.init))
            let вид = набор.first(where: { $0.hasPrefix("nt-") }).map { String($0.dropFirst(3)) } ?? "ok"
            let клик = найти("onclick=\"([^\"]*)\"", в: кусок) ?? ""
            let сделка = найти("openDeal\\('([A-Za-z0-9_-]{1,40})'\\)", в: клик)
            let товар = найти("pid:'([A-Za-z0-9_-]{1,40})'", в: клик)
            let текст = чистыйТекст(найти("<div class=\"n-txt\"[^>]*>(.*?)</div>", в: кусок) ?? "")
            let когда = чистыйТекст(найти("<div class=\"n-when\"><span>([^<]*)</span>", в: кусок) ?? "")
            let повторов = чистыйТекст(найти("<span class=\"n-rep\">([^<]*)</span>", в: кусок) ?? "")
            guard !текст.isEmpty else { continue }
            список.append(УведомлениеКабинета(id: i, вид: вид, новое: набор.contains("nu"), текст: текст, когда: когда,
                                              повторов: повторов, сделка: сделка, товар: товар))
        }
        return список
    }

    /// Первая группа совпадения; точка ловит и переводы строк (текст записи сервер переносит).
    private static func найти(_ шаблон: String, в тексте: String) -> String? {
        guard let выражение = try? NSRegularExpression(pattern: шаблон, options: [.dotMatchesLineSeparators]) else {
            return nil
        }
        let весь = NSRange(тексте.startIndex..., in: тексте)
        guard let совпадение = выражение.firstMatch(in: тексте, options: [], range: весь),
              совпадение.numberOfRanges > 1,
              let r = Range(совпадение.range(at: 1), in: тексте) else { return nil }
        return String(тексте[r])
    }

    /// Теги прочь, сущности HTML — в буквы, пробелы — одним.
    static func чистыйТекст(_ html: String) -> String {
        var s = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let сущности: [(String, String)] = [("&nbsp;", " "), ("&laquo;", "«"), ("&raquo;", "»"), ("&quot;", "\""),
                                            ("&#039;", "'"), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">"),
                                            ("&mdash;", "—"), ("&ndash;", "–"), ("&times;", "×"), ("&amp;", "&")]
        for (код, буква) in сущности { s = s.replacingOccurrences(of: код, with: буква) }
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// markAllRead: POST mark_notif_read {csrf}; ответ не читается.
    @MainActor
    static func прочитать() async {
        _ = try? await ИнбоксAPI.отправить("cabinet.php?action=mark_notif_read", тело: [:])
    }
}

/// Кнопка колокольчика в шапке «Кабинета» с точкой непрочитанных.
struct КнопкаКолокольчика: View {
    let новых: Int
    let нажать: () -> Void

    var body: some View {
        Button(action: нажать) {
            Image(systemName: "bell")
                .font(.system(size: 17, weight: .semibold))
                .overlay(alignment: .topTrailing) {
                    if новых > 0 {
                        Circle()
                            .fill(Theme.непрочитано)
                            .frame(width: 9, height: 9)
                            .offset(x: 3, y: -2)
                    }
                }
        }
        .accessibilityLabel(новых > 0 ? ИнбоксText.т("notif_title") + ", " + String(format: AccessText.т("unread"), новых)
                                      : ИнбоксText.т("notif_title"))
    }
}

/// #notif-panel: «Уведомления» и записи — подложка по типу (nt-ok — зелёная, nt-warn и nt-lead — янтарная, nt-bc —
/// голубая, nt-exch — фиолетовая), непрочитанные — жирным с точкой.
struct ЛистУведомлений: View {
    let уведомления: [УведомлениеКабинета]
    /// Запись с чатом объявления: лист закрывается, кабинет кладёт чат в свой стек.
    let чатТовара: (String) -> Void

    @Environment(\.dismiss) private var закрыть

    init(уведомления: [УведомлениеКабинета], чатТовара: @escaping (String) -> Void) {
        self.уведомления = уведомления
        self.чатТовара = чатТовара
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(уведомления) { у in
                        if у.сделка != nil || у.товар != nil {
                            Button {
                                перейти(у)
                            } label: {
                                строка(у, переход: true)
                            }
                            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
                        } else {
                            строка(у, переход: false)
                        }
                    }
                }
                .padding(12)
            }
            .background(Theme.фонСтраницы)
            .navigationTitle(ИнбоксText.т("notif_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(ИнбоксText.т("close")) { закрыть() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func перейти(_ у: УведомлениеКабинета) {
        закрыть()
        if let номер = у.сделка {
            if NativeRouter.доступна(.сделка(id: номер)) { NativeRouter.shared.цель = .сделка(id: номер) }
        } else if let товар = у.товар {
            чатТовара(товар)
        }
    }

    private func фон(_ вид: String) -> Color {
        switch вид {
        case "warn", "lead": return КраскаОбъявлений.предупреждениеФон
        case "bc": return КраскаОбъявлений.инфоФон
        case "exch": return ИнбоксКраска.иФон
        default: return КраскаОбъявлений.хорошоФон
        }
    }

    private func цвет(_ вид: String) -> Color {
        switch вид {
        case "warn", "lead": return КраскаОбъявлений.предупреждениеТекст
        case "bc": return КраскаОбъявлений.инфоТекст
        case "exch": return ИнбоксКраска.иТекст
        default: return КраскаОбъявлений.хорошоТекст
        }
    }

    private func строка(_ у: УведомлениеКабинета, переход: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: у.товар != nil ? "bubble.left" : (у.сделка != nil ? "checkmark.shield" : "bell"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(цвет(у.вид))
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(у.текст)
                    .font(.system(size: 14, weight: у.новое ? Font.Weight.bold : Font.Weight.regular))
                    .foregroundStyle(Theme.текст)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text(у.когда)
                    if !у.повторов.isEmpty { Text(у.повторов).fontWeight(.bold) }
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
            }
            Spacer(minLength: 4)
            if у.новое {
                Circle()
                    .fill(Theme.непрочитано)
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)
                    .accessibilityHidden(true)
            } else if переход {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.текстВторой)
                    .padding(.top, 3)
                    .accessibilityHidden(true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(у.новое ? фон(у.вид) : Theme.поверхность,
                    in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Обращение в поддержку

/// ticket ответа sup_my_get / sup_my_reply.
struct ОбращениеВПоддержку: Equatable {
    struct Сообщение: Identifiable, Equatable {
        let id: Int
        let отПоддержки: Bool
        let текст: String
        let когда: String
    }

    let id: String
    let статус: String
    let тема: String
    let сообщения: [Сообщение]

    init?(_ t: [String: Any]?) {
        typealias З = МоиОбъявленияAPI
        guard let t else { return nil }
        id = З.строка(t["id"])
        статус = З.строка(t["status"])
        тема = З.строка(t["topic_lbl"])
        var список: [Сообщение] = []
        for (i, m) in ((t["messages"] as? [[String: Any]]) ?? []).enumerated() {
            список.append(Сообщение(id: i, отПоддержки: З.строка(m["from"]) == "staff", текст: З.строка(m["text"]),
                                    когда: З.строка(m["at"])))
        }
        сообщения = список
    }

    /// supRender: new «Новое», answered «Есть ответ», waiting «Ждём вас», closed «Закрыто», иначе как есть.
    var статусТекст: String {
        switch статус {
        case "new": return ИнбоксText.т("sup_st_new")
        case "answered": return ИнбоксText.т("sup_st_answered")
        case "waiting": return ИнбоксText.т("sup_st_waiting")
        case "closed": return ИнбоксText.т("sup_st_closed")
        default: return статус
        }
    }
}

/// Окно обращения (#sup-ov): заголовок — тема или «Обращение в поддержку», подзаголовок «#<8 знаков> · <статус>»,
/// переписка («Поддержка» / «Вы» · «ГГГГ-ММ-ДД ЧЧ:ММ»), поле «Ваш ответ…».
struct ЭкранОбращения: View {
    let номер: String

    @State private var обращение: ОбращениеВПоддержку? = nil
    @State private var ошибка: String? = nil
    @State private var загружено = false
    @State private var ответ = ""
    @State private var отправляем = false
    @State private var плашка: String? = nil
    @FocusState private var полеВФокусе: Bool

    init(номер: String) {
        self.номер = номер
    }

    private func т(_ ключ: String) -> String { ИнбоксText.т(ключ) }
    private typealias З = МоиОбъявленияAPI

    var body: some View {
        VStack(spacing: 0) {
            if !загружено {
                Text(т("loading"))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.текстВторой)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let обращение {
                переписка(обращение)
                ПолеПерепискиСайта(текст: $ответ, можно: можноОтправить, отправить: { отправить() },
                                   фокус: $полеВФокусе, подсказка: т("sup_ph"))
            } else {
                Text(ошибка ?? т("err_generic"))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.текстВторой)
                    .multilineTextAlignment(.center)
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.фонСтраницы)
        .navigationTitle(заголовок)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(заголовок)
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(Theme.текст)
                        .lineLimit(1)
                    if let обращение {
                        Text("#" + String(обращение.id.prefix(8)) + " · " + обращение.статусТекст)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.текстВторой)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
            }
        }
        .toolbarBackground(Theme.поверхность, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .tint(Theme.акцент)
        .task { await загрузить() }
        .overlay(alignment: .bottom) {
            ПлашкаИнбокса(текст: плашка)
                .padding(.bottom, 60)
        }
    }

    private var заголовок: String {
        let тема = обращение?.тема ?? ""
        return тема.isEmpty ? т("sup_title") : тема
    }

    private var можноОтправить: Bool {
        !отправляем && !ответ.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func переписка(_ о: ОбращениеВПоддержку) -> some View {
        ScrollViewReader { прокрутка in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if о.сообщения.isEmpty {
                        Text(т("sup_empty"))
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.текстВторой)
                            .padding(.top, 30)
                    }
                    ForEach(о.сообщения) { м in
                        сообщение(м).id(м.id)
                    }
                    Color.clear.frame(height: 1).id("низ")
                }
                .padding(12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear { прокрутка.scrollTo("низ", anchor: .bottom) }
            .onChange(of: о.сообщения.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) { прокрутка.scrollTo("низ", anchor: .bottom) }
            }
        }
    }

    private func сообщение(_ м: ОбращениеВПоддержку.Сообщение) -> some View {
        let моё = !м.отПоддержки
        let когда = String(м.когда.prefix(16)).replacingOccurrences(of: "T", with: " ")
        return HStack(spacing: 0) {
            if моё { Spacer(minLength: 48) }
            VStack(alignment: .leading, spacing: 4) {
                Text(м.текст)
                    .font(.system(size: 15))
                    .foregroundStyle(моё ? Color.white : Theme.текст)
                Text(т(моё ? "sup_you" : "sup_staff") + " · " + когда)
                    .font(.system(size: 11))
                    .foregroundStyle(моё ? Color.white.opacity(0.75) : Theme.текстВторой)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(моё ? Theme.пузырьМой : Theme.поверхность,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                if !моё {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.линия, lineWidth: 1)
                }
            }
            if !моё { Spacer(minLength: 48) }
        }
        .accessibilityElement(children: .combine)
    }

    /// openTicket: GET sup_my_get&id=; not_found — «Обращение не найдено».
    private func загрузить() async {
        do {
            let j = try await ИнбоксAPI.получить("cabinet.php?action=sup_my_get&id=" + ИнбоксAPI.вАдрес(номер))
            if let j, З.да(j["ok"]), let о = ОбращениеВПоддержку(j["ticket"] as? [String: Any]) {
                обращение = о
                ошибка = nil
            } else if let j, З.строка(j["error"]) == "not_found" {
                ошибка = т("sup_notfound")
            } else if let j, З.нетСессии(j) {
                ошибка = т("sup_auth")
            } else {
                ошибка = ИнбоксAPI.текстОшибки(j, запасной: т("err_generic"))
            }
        } catch {
            ошибка = ИнбоксAPI.текстСбоя(error)
        }
        загружено = true
    }

    /// supSend: POST sup_my_reply {csrf, id, text} → ticket (перерисовка); отказ — error или «Ошибка».
    private func отправить() {
        let текст = ответ.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !текст.isEmpty, !отправляем else { return }
        отправляем = true
        Task { @MainActor in
            defer { отправляем = false }
            do {
                let j = try await ИнбоксAPI.отправить("cabinet.php?action=sup_my_reply", тело: ["id": номер, "text": текст])
                if З.да(j["ok"]) {
                    ответ = ""
                    if let о = ОбращениеВПоддержку(j["ticket"] as? [String: Any]) { обращение = о }
                } else {
                    let причина = З.строка(j["error"])
                    показать(причина.isEmpty ? т("err_generic") : причина)
                }
            } catch {
                показать(т("err_net"))
            }
        }
    }

    private func показать(_ текст: String) {
        плашка = текст
        UIAccessibility.post(notification: .announcement, argument: текст)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            if плашка == текст { плашка = nil }
        }
    }
}

/// «Запросить данные» (dataReqOpen('')): заголовок, пояснение, поле с заготовкой «Прошу выслать данные моей переписки.
/// Что нужно: », «Отправить обращение» (от 10 знаков) → «Обращение принято. Номер: {id}. Ответ придёт в поддержке.».
struct ОкноЗапросаДанных: View {
    @Environment(\.dismiss) private var закрыть
    @State private var текст = ИнбоксText.т("dreq_prefill")
    @State private var сообщение: String? = nil
    @State private var хорошо = false
    @State private var отправляем = false
    @State private var отправлено = false

    init() {}

    private func т(_ ключ: String) -> String { ИнбоксText.т(ключ) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(т("dreq_subtitle"))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                    TextField("", text: $текст, axis: .vertical)
                        .lineLimit(4...8)
                        .font(.system(size: 15))
                        .padding(12)
                        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                                .strokeBorder(Theme.линия, lineWidth: 1)
                        }
                        .accessibilityLabel(т("dreq_title"))
                        .disabled(отправлено)
                    if let сообщение {
                        Text(сообщение)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(хорошо ? КраскаОбъявлений.хорошоТекст : КраскаОбъявлений.плохоТекст)
                    }
                    if !отправлено {
                        Button {
                            отправить()
                        } label: {
                            Text(т(отправляем ? "dreq_sending" : "dreq_submit"))
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.white)
                                .frame(maxWidth: .infinity, minHeight: 46)
                                .background(Theme.зелёный, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                        }
                        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
                        .disabled(отправляем)
                    }
                }
                .padding(16)
            }
            .background(Theme.фонСтраницы)
            .navigationTitle(т("dreq_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(т("close")) { закрыть() }
                }
            }
        }
    }

    private func отправить() {
        let чистый = текст.trimmingCharacters(in: .whitespacesAndNewlines)
        guard чистый.count >= 10 else {
            хорошо = false
            сообщение = т("dreq_min_length")
            return
        }
        guard !отправляем else { return }
        отправляем = true
        Task { @MainActor in
            defer { отправляем = false }
            do {
                let тело: [String: Any] = ["topic": "data", "text": чистый, "ref": "", "website": "", "ft": 9999]
                let j = try await ИнбоксAPI.отправитьБезТокена("support.php?action=create", тело: тело)
                if МоиОбъявленияAPI.да(j["ok"]) {
                    хорошо = true
                    отправлено = true
                    сообщение = т("dreq_success_msg").replacingOccurrences(of: "{id}",
                                                                          with: МоиОбъявленияAPI.строка(j["id"]))
                    UIAccessibility.post(notification: .announcement, argument: т("dreq_success_toast"))
                } else {
                    хорошо = false
                    let причина = МоиОбъявленияAPI.строка(j["error"])
                    сообщение = причина.isEmpty ? т("dreq_error") : причина
                }
            } catch {
                хорошо = false
                сообщение = т("err_no_conn")
            }
        }
    }
}
