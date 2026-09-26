import SwiftUI
import UIKit

/**
 «МОИ ОБЪЯВЛЕНИЯ» — ОКНА, «ДОСТУПНО», «РАБОТА», «ПОДЕЛИТЬСЯ» (этап 41, владелец 26.09.2026: «всё одно и то же, просто
 код разный»).

 Окна — #mod-overlay сайта (.mod-box: значок, заголовок, текст на цветной подложке, кнопки во всю ширину) и окна
 подтверждения с выбором. Карточка «Доступно» — renderSlotBanner, строки «Работы» — _jbRow, лист «Поделиться» —
 showSocialModal(…, "share") без студии роликов (модуль reel сайта) и без автопостинга (интеграции — отдельная область).
 */

// MARK: - Окно поверх списка

struct ОкноМоихОбъявлений: View {
    let окно: МоиОбъявленияМодель.Окно
    /// Идёт запрос («Отправить на ручную проверку») — кнопки неактивны.
    let занято: Bool
    let закрыть: () -> Void
    let одобрено: () -> Void
    let ожидание: () -> Void
    let наРучную: (String) -> Void
    let расширить: () -> Void
    let верификация: () -> Void
    let кОстатку: (String) -> Void

    private func т(_ ключ: String) -> String { МоиОбъявленияText.т(ключ) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            VStack(spacing: 14) {
                содержимое
            }
            .padding(22)
            .frame(maxWidth: 380)
            .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.xl, style: .continuous))
            .padding(.horizontal, 24)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
    }

    @ViewBuilder
    private var содержимое: some View {
        switch окно {
        case .проверка(let шаг, let процент):
            проверка(шаг: шаг, процент: процент)
        case .одобрено(let секунд):
            значок("checkmark.circle", цвет: КраскаОбъявлений.хорошоТекст)
            заголовок(т("republish_t"), цвет: Theme.текст)
            текст(т("republish_b"), фон: КраскаОбъявлений.хорошоФон, цвет: КраскаОбъявлений.хорошоТекст)
            главная(т("btn_ok") + " · " + String(секунд) + т("sec_short"), действие: одобрено)
        case .отклонено(let причина):
            значок("xmark.circle", цвет: КраскаОбъявлений.плохоТекст)
            заголовок(т("rej_t"), цвет: Theme.текст)
            текст(причина, фон: КраскаОбъявлений.плохоФон, цвет: КраскаОбъявлений.плохоТекст)
            главная(т("rej_ok"), действие: закрыть)
        case .ждём:
            значок("hourglass", цвет: Theme.оранжевый)
            заголовок(т("wait_t"), цвет: Theme.текст)
            текст(т("wait_b"), фон: КраскаОбъявлений.инфоФон, цвет: КраскаОбъявлений.инфоТекст)
            главная(т("btn_ok"), действие: ожидание)
        case .блокИИ(let часы, let id):
            значок("nosign", цвет: КраскаОбъявлений.плохоТекст)
            заголовок(т("ai_blk_t"), цвет: КраскаОбъявлений.плохоТекст)
            текст(String(format: т("ai_blk_b"), часы) + "\n\n" + т("ai_blk_s"), фон: КраскаОбъявлений.плохоФон,
                  цвет: КраскаОбъявлений.плохоТекст)
            if let id {
                главная(т("to_manual"), действие: { наРучную(id) })
                    .disabled(занято)
            }
            вторая(т("close"), действие: закрыть)
        case .запрещено(let заголовокОкна, let текстОкна):
            значок("exclamationmark.triangle", цвет: КраскаОбъявлений.плохоТекст)
            заголовок(заголовокОкна, цвет: Theme.текст)
            текст(текстОкна, фон: КраскаОбъявлений.плохоФон, цвет: КраскаОбъявлений.плохоТекст)
            главная(т("ok_btn"), действие: закрыть)
        case .верификация(let причина):
            значок("checkmark.shield", цвет: Theme.акцент)
            заголовок(т("need_verify_t"), цвет: Theme.текст)
            if !причина.isEmpty { текст(причина, фон: Theme.поверхность2, цвет: Theme.текст) }
            главная(т("need_verify_go"), действие: верификация)
            вторая(т("later"), действие: закрыть)
        case .лимит(let текстЛимита, let нуженаВерификация):
            значок("square.stack.3d.up", цвет: КраскаОбъявлений.предупреждениеТекст)
            заголовок(т("limit_t"), цвет: Theme.текст)
            текст(текстЛимита, фон: КраскаОбъявлений.предупреждениеФон, цвет: КраскаОбъявлений.предупреждениеТекст)
            /* «Расширить лимит» — покупка слотов: только страница сайта (Config.цифровыеПокупки). */
            главная(т("limit_slots"), действие: расширить)
            if нуженаВерификация { вторая(т("limit_verify"), действие: верификация) }
            вторая(т("later"), действие: закрыть)
        case .ждутТовар(let id, let сколько):
            значок("hand.raised", цвет: Theme.акцент)
            заголовок(String(format: т("wl_hint_t"), сколько), цвет: Theme.текст)
            текст(т("wl_hint_m"), фон: Theme.поверхность2, цвет: Theme.текст)
            главная(т("wl_hint_go"), действие: { кОстатку(id) })
            вторая(т("later"), действие: закрыть)
        }
    }

    /// «Kliko AI проверяет объявление»: шаг, полоса, проценты — закрыть нельзя, как у сайта.
    private func проверка(шаг: String, процент: Int) -> some View {
        VStack(spacing: 12) {
            значок("cpu", цвет: Theme.текстВторой)
            заголовок(т("mod_title"), цвет: Theme.текст)
            Text(шаг)
                .font(.system(size: 14))
                .foregroundStyle(Theme.текстВторой)
            ProgressView(value: Double(min(100, max(0, процент))), total: 100)
                .tint(Theme.зелёный2)
                .animation(ДвижениеСайта.прогресс, value: процент)
            Text(String(процент) + "%")
                .font(.system(size: 13, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.текст)
        }
        .accessibilityElement(children: .combine)
    }

    private func значок(_ символ: String, цвет: Color) -> some View {
        Image(systemName: символ)
            .font(.system(size: 40, weight: .semibold))
            .foregroundStyle(цвет)
            .accessibilityHidden(true)
    }

    private func заголовок(_ текст: String, цвет: Color) -> some View {
        Text(текст)
            .font(.system(size: 18, weight: .heavy))
            .foregroundStyle(цвет)
            .multilineTextAlignment(.center)
            .accessibilityAddTraits(.isHeader)
    }

    private func текст(_ содержание: String, фон: Color, цвет: Color) -> some View {
        Text(содержание)
            .font(.system(size: 14))
            .foregroundStyle(цвет)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(фон, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
    }

    private func главная(_ подпись: String, действие: @escaping () -> Void) -> some View {
        Button(action: действие) {
            Text(подпись)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(Theme.зелёный, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
    }

    private func вторая(_ подпись: String, действие: @escaping () -> Void) -> some View {
        Button(action: действие) {
            Text(подпись)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.текст)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                        .strokeBorder(Theme.линия, lineWidth: 1.5)
                }
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
    }
}

// MARK: - «Доступно»: Kliko AI и слоты

/**
 renderSlotBanner сайта: видна, если CAB_AI.show или слоты заняты на 90 % и больше. Кнопки «Расширить» и «Пакет Kliko AI» —
 покупки (Config.цифровыеПокупки = false): ведут на страницу кабинета сайта; «Верификация» — на ?go=verify.
 */
struct КарточкаДоступно: View {
    let ии: КабинетСайта.КвотаИИ?
    let слоты: СлотыОбъявлений?
    let товары: [МоёОбъявление]
    let расширить: () -> Void
    let верификация: () -> Void

    private func т(_ ключ: String) -> String { МоиОбъявленияText.т(ключ) }

    private var видна: Bool {
        if ии?.показать == true { return true }
        guard let с = слоты, с.лимит > 0 else { return false }
        return Double(с.занято) / Double(с.лимит) >= 0.9
    }

    var body: some View {
        if видна {
            VStack(alignment: .leading, spacing: 12) {
                Text(т("stat_title"))
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.текстВторой)
                    .textCase(.uppercase)
                    .accessibilityAddTraits(.isHeader)
                if let квота = ии, квота.показать { сегментИИ(квота) }
                if let с = слоты { сегментСлотов(с) }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                    .strokeBorder(Theme.линия, lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private func сегментИИ(_ к: КабинетСайта.КвотаИИ) -> some View {
        if к.бесплатно {
            сегмент(символ: "sparkles", заголовок: к.название, счёт: Text(к.бесплатноЗаголовок).bold(),
                    доля: nil, подпись: к.бесплатноПодпись, кнопка: nil, действие: nil)
        } else if к.оплачено {
            сегмент(символ: "sparkles", заголовок: к.название, счёт: Text(к.безлимит + " ✓").bold(),
                    доля: 1, подпись: "", кнопка: nil, действие: nil)
        } else {
            let доля: Double = к.лимит > 0 ? min(1, Double(к.осталось) / Double(к.лимит)) : 0
            let счёт: Text = к.осталось > 0
                ? Text(к.осталосьПодпись + " ") + Text(String(к.осталось)).bold() + Text(" / " + String(к.лимит))
                : Text(т("ai_over")).bold()
            сегмент(символ: "sparkles", заголовок: к.название, счёт: счёт, доля: к.осталось > 0 ? max(0.04, доля) : 0,
                    подпись: к.осталось <= 0 ? т("slot_full_sub") : "",
                    кнопка: к.верифицирован ? к.кнопкаПакета : к.кнопкаВерификации,
                    действие: к.верифицирован ? расширить : верификация)
        }
    }

    private func сегментСлотов(_ с: СлотыОбъявлений) -> some View {
        let свободно = max(0, с.лимит - с.занято)
        let доля: Double = с.лимит > 0 ? min(1, Double(свободно) / Double(с.лимит)) : 0
        let полно = с.занято >= с.лимит
        let счёт: Text = Text(т("slot_free") + " ") + Text(String(свободно)).bold() + Text(" / " + String(с.лимит))
        return сегмент(символ: "square.stack.3d.up", заголовок: т("cab_listings"), счёт: счёт,
                       доля: свободно > 0 ? max(0.04, доля) : 0, подпись: подписьСлотов(с, полно: полно),
                       кнопка: т("cab_expand"), действие: расширить)
    }

    /// «Лимит достигнут · слот освободится через N дн.» или «тариф N ещё N дн.» — как считает сайт (карта §3.3.9).
    private func подписьСлотов(_ с: СлотыОбъявлений, полно: Bool) -> String {
        let сейчас = Date()
        if полно {
            var текст = т("slot_full_sub")
            if let дней = ближайшийСлот(сейчас) { текст += " · " + String(format: т("slot_free_in"), дней) }
            return текст
        }
        if с.тариф > с.бесплатно, let конец = Self.дата(с.до) {
            let дней = Int((конец.timeIntervalSince(сейчас) / 86_400).rounded(.up))
            if дней > 0 { return String(format: т("slot_plan"), с.тариф, дней) }
        }
        return ""
    }

    /// min(30 − полных суток с created_at) по approved / pending / pending_manual и inactive на паузе, не меньше 0.
    private func ближайшийСлот(_ сейчас: Date) -> Int? {
        var ближайший: Int? = nil
        for товар in товары {
            let считается = товар.статус == "approved" || товар.статус == "pending" || товар.статус == "pending_manual"
                || (товар.статус == "inactive" && товар.пауза)
            guard считается, let создано = Self.дата(товар.создано) else { continue }
            let дней = 30 - Int((сейчас.timeIntervalSince(создано) / 86_400).rounded(.down))
            if ближайший == nil || дней < (ближайший ?? дней) { ближайший = дней }
        }
        return ближайший.map { max(0, $0) }
    }

    /// Date.parse сайта для строк сервера: ISO 8601 или «YYYY-MM-DD HH:MM[:SS]» / «YYYY-MM-DD». Не разобралась — nil,
    /// и подпись без числа (как у сайта при NaN).
    static func дата(_ строка: String) -> Date? {
        let чистая = строка.trimmingCharacters(in: .whitespaces)
        guard !чистая.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        if let д = iso.date(from: чистая) { return д }
        let формат = DateFormatter()
        формат.locale = Locale(identifier: "en_US_POSIX")
        формат.timeZone = TimeZone(identifier: "Asia/Almaty")
        for шаблон in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            формат.dateFormat = шаблон
            if let д = формат.date(from: чистая) { return д }
        }
        return nil
    }

    private func сегмент(символ: String, заголовок: String, счёт: Text, доля: Double?, подпись: String,
                         кнопка: String?, действие: (() -> Void)?) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: символ)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.акцент)
                .frame(width: 34, height: 34)
                .background(Theme.мята, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(заголовок)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.текст)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    счёт
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.текст)
                        .lineLimit(1)
                }
                if let доля {
                    GeometryReader { гео in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.поверхность2)
                            Capsule().fill(Theme.зелёный2).frame(width: гео.size.width * CGFloat(доля))
                        }
                    }
                    .frame(height: 5)
                    .accessibilityHidden(true)
                }
                if !подпись.isEmpty {
                    Text(подпись)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let надпись = кнопка, !надпись.isEmpty, let нажать = действие {
                Button(action: нажать) {
                    Text(надпись)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.акцент)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Theme.оттенокАкцента, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - «Работа»

/// Строка вакансии или резюме (_jbRow): метки, имя, компания, зарплата и город, кнопки.
struct СтрокаРаботы: View {
    enum Действие { case восстановить, снять, изменить, вТоп }

    let запись: МояРабота
    let занято: Bool
    let действие: (Действие) -> Void

    private func т(_ ключ: String) -> String { МоиОбъявленияText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            метки
            Text(заголовок)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.текст)
            if !подзаголовок.isEmpty {
                Text(подзаголовок)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
            }
            if !сведения.isEmpty {
                Text(сведения)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
            }
            кнопки
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
        .opacity(запись.истёк ? 0.8 : 1)
    }

    private var заголовок: String {
        if запись.вакансия { return запись.название }
        return запись.имя.isEmpty ? т("hov_resume") : запись.имя
    }

    private var подзаголовок: String { запись.вакансия ? запись.компания : запись.название }

    /// «100 000 – 200 000 ₸ · Алматы»: верхняя граница — только у вакансии, как у сайта.
    private var сведения: String {
        var части: [String] = []
        if запись.зарплатаОт > 0 {
            var з = DesignText.число(Int(запись.зарплатаОт))
            if запись.вакансия && запись.зарплатаДо > 0 { з += " – " + DesignText.число(Int(запись.зарплатаДо)) }
            части.append(з + "\u{00A0}₸")
        }
        if !запись.город.isEmpty { части.append(запись.город) }
        return части.joined(separator: " · ")
    }

    private var метки: some View {
        HStack(spacing: 6) {
            метка(т(запись.вакансия ? "hov_vacancy" : "hov_resume"), фон: КраскаОбъявлений.хорошоФон,
                  цвет: КраскаОбъявлений.хорошоТекст)
            if запись.топ { метка("★ " + т("badge_top"), фон: Theme.топФон, цвет: Theme.золото) }
            if запись.истёк { метка(т("jb_expired"), фон: КраскаОбъявлений.плохоФон, цвет: КраскаОбъявлений.плохоТекст) }
        }
    }

    private func метка(_ текст: String, фон: Color, цвет: Color) -> some View {
        Text(текст)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(цвет)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(фон, in: Capsule())
    }

    @ViewBuilder
    private var кнопки: some View {
        HStack(spacing: 6) {
            if запись.истёк {
                КнопкаКарточки(подпись: т("jb_restore"), значок: "arrow.uturn.backward", вид: .вперёд) {
                    действие(.восстановить)
                }
                КнопкаКарточки(подпись: т("jb_delete"), значок: "trash", вид: .удалить) { действие(.снять) }
            } else {
                /* «В ТОП» у резюме — платно (Config.цифровыеПокупки): страница кабинета сайта. */
                if !запись.вакансия && !запись.топ {
                    КнопкаКарточки(подпись: т("jb_top"), значок: "arrow.up", вид: .топ) { действие(.вТоп) }
                }
                КнопкаКарточки(подпись: т("jb_edit"), значок: "pencil", вид: .обычная) { действие(.изменить) }
                КнопкаКарточки(подпись: т("jb_off"), значок: "pause.fill", вид: .обычная) { действие(.снять) }
            }
        }
        .disabled(занято)
    }
}

// MARK: - «Поделиться»

/**
 showSocialModal(…, "share") и socialQuickShare сайта: превью, WhatsApp, Telegram, «Ссылка» (в буфер «{название} — {цена}
 ₸\n{адрес}»), «Позже». Адрес — /marketplace.php?item=<id> от корня сайта, как location.origin + "/marketplace.php?item=".
 */
struct ЛистПоделитьсяОбъявлением: View {
    let товар: МоёОбъявление
    let скопировано: () -> Void
    @Environment(\.dismiss) private var закрыть

    init(товар: МоёОбъявление, скопировано: @escaping () -> Void) {
        self.товар = товар
        self.скопировано = скопировано
    }

    private func т(_ ключ: String) -> String { МоиОбъявленияText.т(ключ) }

    private var адрес: String {
        let номер = товар.id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? товар.id
        return (Config.url("/marketplace.php?item=" + номер)?.absoluteString) ?? ""
    }

    /// «{название} — 12 000 ₸» (toLocaleString("ru-RU") сайта; без цены — только название).
    private var подпись: String {
        товар.цена > 0 ? товар.название + " — " + DesignText.число(Int(товар.цена)) + " ₸" : товар.название
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(т("share_t"))
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .accessibilityAddTraits(.isHeader)
            превью
            HStack(spacing: 10) {
                кнопка("WhatsApp", символ: "message.fill", цвет: Theme.whatsApp) {
                    внешняя("https://wa.me/?text=" + Self.код(подпись + " " + адрес))
                }
                кнопка("Telegram", символ: "paperplane.fill", цвет: Theme.проверен) {
                    внешняя("https://t.me/share/url?url=" + Self.код(адрес) + "&text=" + Self.код(подпись))
                }
                кнопка(т("share_link"), символ: "link", цвет: Theme.акцент) {
                    UIPasteboard.general.string = подпись + "\n" + адрес
                    закрыть()
                    скопировано()
                }
            }
            Button(т("later")) { закрыть() }
                .font(.system(size: 15, weight: .semibold))
                .tint(Theme.текстВторой)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var превью: some View {
        HStack(spacing: 12) {
            КартинкаЛенты(Config.url(товар.фото), пунктов: 56) {
                Theme.поверхность2
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(товар.название)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.текст)
                    .lineLimit(2)
                Text(товар.цена > 0 ? DesignText.число(Int(товар.цена)) + "\u{00A0}₸" : т("price_negotiable"))
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.акцент)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func кнопка(_ подпись: String, символ: String, цвет: Color, действие: @escaping () -> Void) -> some View {
        Button(action: действие) {
            VStack(spacing: 6) {
                Image(systemName: символ)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 48, height: 48)
                    .background(цвет, in: Circle())
                    .accessibilityHidden(true)
                Text(подпись)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.текст)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.95))
    }

    private func внешняя(_ строка: String) {
        guard let u = URL(string: строка) else { return }
        UIApplication.shared.open(u)
        закрыть()
    }

    /// encodeURIComponent: всё, кроме A–Z a–z 0–9 - _ . ! ~ * ' ( ).
    static func код(_ текст: String) -> String {
        let можно = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.!~*'()")
        return текст.addingPercentEncoding(withAllowedCharacters: можно) ?? текст
    }
}
