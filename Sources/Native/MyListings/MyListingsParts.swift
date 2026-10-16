import SwiftUI
import UIKit

/**
 «МОИ ОБЪЯВЛЕНИЯ» — ОКНА, «ДОСТУПНО», «РАБОТА», «ПОДЕЛИТЬСЯ» (этап 41, владелец 26.09.2026: «всё одно и то же, просто
 код разный»).

 Окна — #mod-overlay сайта (.mod-box: значок, заголовок, текст на цветной подложке, кнопки во всю ширину) и окна
 подтверждения с выбором. Карточка «Доступно» — renderSlotBanner, строки «Работы» — _jbRow. Окно «Поделиться»
 (showSocialModal сайта) — ОкноПоделитьсяКабинета в CabinetShare.swift.
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
    let верификация: () -> Void
    let кОстатку: (String) -> Void
    /// «Расширить лимит» — окно покупки App Store той услуги, что поднимает слоты (РасширениеЛимита.слоты: тариф слотов,
    /// комбо, PRO); кнопка только при Config.цифровыеПокупки и загруженном или грузящемся товаре.
    var расширить: (ВидУслугиApple) -> Void = { _ in }
    /// Товары App Store: появились — «Расширить лимит» встаёт в окно сама.
    @ObservedObject private var покупки = ПокупкиApple.shared

    init(окно: МоиОбъявленияМодель.Окно, занято: Bool, закрыть: @escaping () -> Void, одобрено: @escaping () -> Void,
         ожидание: @escaping () -> Void, наРучную: @escaping (String) -> Void, верификация: @escaping () -> Void,
         кОстатку: @escaping (String) -> Void, расширить: @escaping (ВидУслугиApple) -> Void = { _ in }) {
        self.окно = окно
        self.занято = занято
        self.закрыть = закрыть
        self.одобрено = одобрено
        self.ожидание = ожидание
        self.наРучную = наРучную
        self.верификация = верификация
        self.кОстатку = кОстатку
        self.расширить = расширить
    }

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
            кнопкиЛимита(нужна: нуженаВерификация)
        case .ждутТовар(let id, let сколько):
            значок("hand.raised", цвет: Theme.акцент)
            заголовок(String(format: т("wl_hint_t"), сколько), цвет: Theme.текст)
            текст(т("wl_hint_m"), фон: Theme.поверхность2, цвет: Theme.текст)
            главная(т("wl_hint_go"), действие: { кОстатку(id) })
            вторая(т("later"), действие: закрыть)
        }
    }

    /**
     Кнопки окна «Вы достигли лимита!» (владелец 16.10.2026: «в окне предлагать расширить сразу»): «Расширить лимит» —
     главной, покупка App Store по цепочке слоты → комбо → PRO; товар ещё грузится — та же кнопка с колесом. Верификация
     (+5) — второй, где сервер её просит, затем «Позже». Купить нечего — верификация или «Понятно», и окно ещё раз
     спрашивает App Store: товар придёт — кнопка встанет сама.
     */
    @ViewBuilder
    private func кнопкиЛимита(нужна: Bool) -> some View {
        if РасширениеЛимита.есть(РасширениеЛимита.слоты) {
            КнопкаРасширения(цепочка: РасширениеЛимита.слоты, действие: расширить) { занято, нажать in
                ГлавнаяКнопкаЛимита(подпись: т("limit_slots"), занято: занято, действие: нажать)
            }
            if нужна { вторая(т("limit_verify"), действие: верификация) }
            вторая(т("later"), действие: закрыть)
        } else if нужна {
            главная(т("limit_verify"), действие: верификация)
                .task { await ПокупкиApple.shared.подгрузить() }
            вторая(т("later"), действие: закрыть)
        } else {
            главная(т("ok_btn"), действие: закрыть)
                .task { await ПокупкиApple.shared.подгрузить() }
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
 renderSlotBanner сайта: видна, если CAB_AI.show или слоты заняты на 90 % и больше. «Расширить» и «Пакет Kliko AI» —
 окно покупки App Store, только при Config.цифровыеПокупки и загруженном товаре услуги (единое правило
 ДоступПокупкиApple; иначе nil — кнопок нет, одни сведения); «Верификация» — окно верификации. С 16.10.2026 (владелец:
 «в окне предлагать расширить сразу») «Расширить» берёт первую загруженную услугу из РасширениеЛимита.слоты (слоты,
 комбо, PRO), при полных слотах залит зелёным; Kliko AI на нуле — «Больше Kliko AI» (РасширениеЛимита.ии).
 */
struct КарточкаДоступно: View {
    let ии: КабинетСайта.КвотаИИ?
    let слоты: СлотыОбъявлений?
    let товары: [МоёОбъявление]
    let верификация: () -> Void
    /// Покупка того, что поднимает слоты (App Store, РасширениеЛимита.слоты: тариф слотов, комбо, PRO). nil — кнопки нет.
    var расширить: ((ВидУслугиApple) -> Void)? = nil
    /// Покупка того, что снимает лимит Kliko AI (РасширениеЛимита.ии: пакет Kliko AI, комбо, PRO). nil — кнопки нет.
    var пакетИИ: ((ВидУслугиApple) -> Void)? = nil
    /// IS_VERIFIED страницы кабинета: нет — при полных слотах под подписью «Пройти верификацию (+5)».
    var верифицирован = true
    /// Товары App Store: кнопки покупки — только когда товар услуги загружен.
    @ObservedObject private var покупки = ПокупкиApple.shared

    init(ии: КабинетСайта.КвотаИИ?, слоты: СлотыОбъявлений?, товары: [МоёОбъявление], верификация: @escaping () -> Void,
         расширить: ((ВидУслугиApple) -> Void)? = nil, пакетИИ: ((ВидУслугиApple) -> Void)? = nil,
         верифицирован: Bool = true) {
        self.ии = ии
        self.слоты = слоты
        self.товары = товары
        self.верификация = верификация
        self.расширить = расширить
        self.пакетИИ = пакетИИ
        self.верифицирован = верифицирован
    }

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
                if let квота = ии, квота.показать {
                    сегментИИ(квота)
                    /* Ссылка «Свой ИИ» под «Kliko AI-ассистент», как у сайта; только при own_ai.on. */
                    СсылкаСвоегоИИ()
                }
                if let с = слоты { сегментСлотов(с) }
            }
            .task { await СвойИИМодель.shared.загрузитьЛениво() }
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
        } else if к.осталось <= 0 && пакетИИ != nil && РасширениеЛимита.есть(РасширениеЛимита.ии) {
            /* Kliko AI закончился (владелец 16.10.2026: «в окне предлагать расширить сразу»): «Больше Kliko AI» —
               залитым чипом даже без верификации (пакет Kliko AI, комбо или PRO), верификация — ссылкой ниже. */
            let вид = РасширениеЛимита.вид(РасширениеЛимита.ии)
            VStack(alignment: .leading, spacing: 6) {
                сегмент(символ: "sparkles", заголовок: к.название, счёт: Text(т("ai_over")).bold(), доля: 0,
                        подпись: т("slot_full_sub"), кнопка: ЛимитText.т("lu_more_ai"),
                        действие: нажатиеИИ(вид), главная: true, грузится: вид == nil)
                if !к.верифицирован {
                    ссылкаВерификации(к.кнопкаВерификации.isEmpty ? т("limit_verify") : к.кнопкаВерификации)
                }
            }
        } else {
            let доля: Double = к.лимит > 0 ? min(1, Double(к.осталось) / Double(к.лимит)) : 0
            let счёт: Text = к.осталось > 0
                ? Text(к.осталосьПодпись + " ") + Text(String(к.осталось)).bold() + Text(" / " + String(к.лимит))
                : Text(т("ai_over")).bold()
            let купить: (() -> Void)? = покупки.можноКупить(.пакетИИ) ? нажатие(пакетИИ, .пакетИИ) : nil
            let подписьПакета: String? = купить == nil ? nil : (к.кнопкаПакета.isEmpty ? ПокупкиAppleText.т("ai_pack_btn") : к.кнопкаПакета)
            сегмент(символ: "sparkles", заголовок: к.название, счёт: счёт, доля: к.осталось > 0 ? max(0.04, доля) : 0,
                    подпись: к.осталось <= 0 ? т("slot_full_sub") : "",
                    кнопка: к.верифицирован ? подписьПакета : Optional(к.кнопкаВерификации),
                    действие: к.верифицирован ? купить : Optional(верификация))
        }
    }

    /// Нажатие покупки этой услуги; nil — кнопки нет (нет действия или нечего купить).
    private func нажатие(_ действие: ((ВидУслугиApple) -> Void)?, _ вид: ВидУслугиApple?) -> (() -> Void)? {
        guard let действие, let вид else { return nil }
        return { действие(вид) }
    }

    /// «Больше Kliko AI»: вид ещё не известен (товар грузится) — пустое нажатие, чип с колесом не нажимается.
    private func нажатиеИИ(_ вид: ВидУслугиApple?) -> (() -> Void)? {
        guard let вид else { return {} }
        return нажатие(пакетИИ, вид)
    }

    /// «Расширить» слотов: покупка App Store по цепочке слоты → комбо → PRO; товар ещё грузится — чип с колесом
    /// (пустое нажатие, чип не нажимается); нечего купить — nil, чипа нет.
    private func нажатиеСлотов(грузится: Bool) -> (() -> Void)? {
        if грузится { return {} }
        return нажатие(расширить, РасширениеЛимита.вид(РасширениеЛимита.слоты))
    }

    /// «Пройти верификацию (+5)» — ссылкой под подписью сегмента: верификация бесплатна и тоже поднимает лимит.
    private func ссылкаВерификации(_ подпись: String) -> some View {
        Button(action: верификация) {
            Text(подпись)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.акцент)
                .underline()
                .multilineTextAlignment(.leading)
        }
        .buttonStyle(.plain)
        .padding(.leading, 44)
    }

    /**
     Слоты: «Расширить» прямо в шапке (владелец 16.10.2026, скрин «Лимит достигнут»). Полно — чип залит зелёным, это
     главное действие карточки; неверифицированному ниже ссылка «Пройти верификацию (+5)». Товар App Store ещё не
     пришёл — карточка ещё раз спрашивает App Store (не чаще раза в минуту).
     */
    private func сегментСлотов(_ с: СлотыОбъявлений) -> some View {
        let свободно = max(0, с.лимит - с.занято)
        let доля: Double = с.лимит > 0 ? min(1, Double(свободно) / Double(с.лимит)) : 0
        let полно = с.занято >= с.лимит
        let счёт: Text = Text(т("slot_free") + " ") + Text(String(свободно)).bold() + Text(" / " + String(с.лимит))
        let грузится = расширить != nil && РасширениеЛимита.вид(РасширениеЛимита.слоты) == nil
            && РасширениеЛимита.грузится(РасширениеЛимита.слоты)
        let нажать = нажатиеСлотов(грузится: грузится)
        return VStack(alignment: .leading, spacing: 6) {
            сегмент(символ: "square.stack.3d.up", заголовок: т("cab_listings"), счёт: счёт,
                    доля: свободно > 0 ? max(0.04, доля) : 0, подпись: подписьСлотов(с, полно: полно),
                    кнопка: нажать == nil ? nil : т("cab_expand"), действие: нажать, главная: полно,
                    грузится: грузится)
            if полно && !верифицирован { ссылкаВерификации(т("limit_verify")) }
        }
        .task(id: полно) {
            if полно && расширить != nil { await ПокупкиApple.shared.подгрузить() }
        }
    }

    /// «Лимит достигнут · слот освободится через N дн.» или «тариф N ещё N дн.» — как считает сайт (карта §3.3.9).
    private func подписьСлотов(_ с: СлотыОбъявлений, полно: Bool) -> String {
        let сейчас = Date()
        if полно {
            var текст = т("slot_full_sub")
            /* Меньше суток — «в течение суток», а не «через 0 дн.»; дни — с округлением вверх, как «тариф ещё N дн.». */
            if let осталось = ближайшийСлот(сейчас) {
                текст += " · " + (осталось < 86_400 ? т("slot_free_day")
                                  : String(format: т("slot_free_in"), Int((осталось / 86_400).rounded(.up))))
            }
            return текст
        }
        if с.тариф > с.бесплатно, let конец = Self.дата(с.до) {
            let дней = Int((конец.timeIntervalSince(сейчас) / 86_400).rounded(.up))
            if дней > 0 { return String(format: т("slot_plan"), с.тариф, дней) }
        }
        return ""
    }

    /**
     Сколько секунд до ближайшего освобождения места по approved / pending / pending_manual и inactive на паузе; nil —
     считать нечего. Владелец 16.10.2026 (скрин «место освободится через 0 дн.»): формула сайта (карта §3.3.9) —
     30 − полных суток с created_at, не меньше 0, — у продлённых, с автопродлением и уже истёкших давала 0. Здесь
     сознательно по сроку сервера: конец — life_end (нет его — дата подачи + 30 суток); автопродление место не освободит,
     прошедший срок — уже не «через».
     */
    private func ближайшийСлот(_ сейчас: Date) -> TimeInterval? {
        var ближайший: TimeInterval? = nil
        for товар in товары {
            let считается = товар.статус == "approved" || товар.статус == "pending" || товар.статус == "pending_manual"
                || (товар.статус == "inactive" && товар.пауза)
            guard считается, !товар.автоПродление else { continue }
            let конец: Date
            if товар.конецСрока > 0 {
                конец = Date(timeIntervalSince1970: товар.конецСрока)
            } else if let создано = Self.дата(товар.создано) {
                конец = создано.addingTimeInterval(30 * 86_400)
            } else {
                continue
            }
            let осталось = конец.timeIntervalSince(сейчас)
            guard осталось > 0 else { continue }
            if осталось < (ближайший ?? .infinity) { ближайший = осталось }
        }
        return ближайший
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

    /// главная — чип залит зелёным (лимит достигнут); грузится — товар App Store ещё грузится, чип с колесом.
    private func сегмент(символ: String, заголовок: String, счёт: Text, доля: Double?, подпись: String,
                         кнопка: String?, действие: (() -> Void)?, главная: Bool = false,
                         грузится: Bool = false) -> some View {
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
                ЧипРасширения(подпись: надпись, главная: главная, грузится: грузится, действие: нажать)
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
    /// Товары App Store: «В ТОП» — только когда товар ТОП резюме загружен.
    @ObservedObject private var покупки = ПокупкиApple.shared

    init(запись: МояРабота, занято: Bool, действие: @escaping (Действие) -> Void) {
        self.запись = запись
        self.занято = занято
        self.действие = действие
    }

    private func т(_ ключ: String) -> String { МоиОбъявленияText.т(ключ) }

    var body: some View {
        /* Ровная схема (владелец 13.10.2026: «схема должна быть ровной везде»): у всех строк «Работы» одни и те же слоты
           одной высоты — метки, название, компания (у резюме — должность), «зарплата · город» — каждый ровно в одну
           строку; нет компании или зарплаты — пустая строка той же высоты, длинное — с многоточием (VoiceOver — целиком). */
        VStack(alignment: .leading, spacing: 6) {
            метки
            Text(заголовок)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.текст)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(подзаголовок.isEmpty ? " " : подзаголовок)
                .font(.system(size: 13))
                .foregroundStyle(Theme.текстВторой)
                .lineLimit(1)
                .truncationMode(.tail)
                .accessibilityHidden(подзаголовок.isEmpty)
            Text(сведения.isEmpty ? " " : сведения)
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
                .lineLimit(1)
                .truncationMode(.tail)
                .accessibilityHidden(сведения.isEmpty)
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
            .lineLimit(1)
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
                /* «В ТОП» у резюме — покупка App Store, только при Config.цифровыеПокупки и загруженном товаре
                   (ДоступПокупкиApple); иначе кнопки нет. */
                if покупки.можноКупить(.топРезюме) && !запись.вакансия && !запись.топ {
                    КнопкаКарточки(подпись: т("jb_top"), значок: "arrow.up", вид: .топ) { действие(.вТоп) }
                }
                КнопкаКарточки(подпись: т("jb_edit"), значок: "pencil", вид: .обычная) { действие(.изменить) }
                КнопкаКарточки(подпись: т("jb_off"), значок: "pause.fill", вид: .обычная) { действие(.снять) }
            }
        }
        .disabled(занято)
    }
}
