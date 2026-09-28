import SwiftUI
import UIKit

/**
 КАРТОЧКА «МОЕГО ОБЪЯВЛЕНИЯ» — ЭТАП 41 (владелец 26.09.2026: «всё одно и то же, просто код разный»).

 .adv-card сайта (renderAdvItems, CAB @894913) по порядку: фото 96×84 слева, справа цена (.adv-price), название
 в две строки со значком «ТОП», дата и #номер с кнопкой «Скопировать ID», значок статуса (первый подходящий, как IIFE
 adv-badges сайта), счётчики stats; ниже — «Остался один шаг», причина отклонения, «В ТОПе до …», срок жизни
 с авто-продлением (только approved), склад магазина, список «кто» и кнопки advBtnsHTML.

 Карточка ничего не шлёт сама: всё, что она умеет, — сказать экрану, что нажато (ДействиеКарточки). Вопросы перед
 записью, страницы сайта и запросы — у экрана и модели.
 */

/// Кнопки ряда .adv-acts — как advBtnsHTML. «Продвинуть» / «Продлить ТОП» — только при Config.цифровыеПокупки (покупка
/// через App Store); выключено — кнопки нет.
enum КнопкаОбъявления: Hashable {
    case изменить, смотреть, поделиться, продвинуть, снять, активировать, восстановить, проверить, удалить
    case удалитьНавсегда, наПроверку

    /// Набор и порядок кнопок сайта для вкладки и статуса. «Копии» здесь нет: сайт заполняет ей свой мастер подачи
    /// (duplicateItem) без адреса — она придёт с нативной подачей (этап 42).
    static func набор(_ товар: МоёОбъявление, вкладка: ВкладкаОбъявлений) -> [КнопкаОбъявления] {
        if товар.образец {
            switch вкладка {
            case .published: return [.изменить, .снять, .удалить]
            case .deleted:   return [.восстановить, .удалитьНавсегда]
            case .inactive:  return [.изменить, .активировать, .удалить]
            }
        }
        switch вкладка {
        case .published:
            if Config.цифровыеПокупки { return [.изменить, .смотреть, .поделиться, .продвинуть, .снять] }
            return [.изменить, .смотреть, .поделиться, .снять]
        case .deleted:
            return товар.статус == "deleted_permanent" ? [.наПроверку, .удалитьНавсегда] : [.восстановить, .удалитьНавсегда]
        case .inactive:
            if товар.статус == "pending" || товар.статус == "ai_check" { return [.проверить, .изменить, .удалить] }
            if товар.статус == "pending_manual" {
                return товар.техническаяРучная ? [.проверить, .изменить, .удалить] : [.изменить, .удалить]
            }
            return [.изменить, .активировать, .удалить]
        }
    }

    func подпись(топ: Bool) -> String {
        let т = МоиОбъявленияText.т
        switch self {
        case .изменить:        return т("btn_edit")
        case .смотреть:        return т("btn_view")
        case .поделиться:      return т("btn_share")
        case .продвинуть:      return т(топ ? "btn_extend_top" : "btn_promote")
        case .снять:           return т("btn_pause")
        case .активировать:    return т("btn_activate")
        case .восстановить:    return т("btn_restore")
        case .проверить:       return т("btn_recheck")
        case .удалить:         return т("btn_delete")
        case .удалитьНавсегда: return т("btn_delete_forever")
        case .наПроверку:      return т("btn_edit_recheck")
        }
    }

    var значок: String {
        switch self {
        case .изменить, .наПроверку: return "pencil"
        case .смотреть:              return "eye"
        case .поделиться:            return "square.and.arrow.up"
        case .продвинуть:            return "arrow.up"
        case .снять:                 return "pause.fill"
        case .активировать:          return "play.fill"
        case .восстановить:          return "arrow.uturn.backward"
        case .проверить:             return "arrow.clockwise"
        case .удалить, .удалитьНавсегда: return "trash"
        }
    }
}

/// Что нажали на карточке.
enum ДействиеКарточки {
    case кнопка(КнопкаОбъявления)
    /// Фото или название: одобренное — страница объявления, остальные — правка (advView сайта).
    case открыть
    case автоПродление(Bool)
    case склад(Int)
    /// «Ждут появления» — окно «{n} ждут этот товар».
    case ждут
    /// «Пройти» в блоке «Остался один шаг».
    case верификация
}

/// Краски значков и блоков карточки — переменные сайта --tint-*/--on-*/--edge-* в светлой и тёмной теме.
enum КраскаОбъявлений {
    static let предупреждениеФон = Theme.цвет(светлый: Theme.hex(0xFFF4E5), тёмный: Theme.hex(0xE0BD5E, 0.15))
    static let предупреждениеТекст = Theme.цвет(0x92400E, 0xE0BD5E)
    static let предупреждениеКромка = Theme.цвет(светлый: Theme.hex(0xFDE68A), тёмный: Theme.hex(0xE0BD5E, 0.34))
    static let плохоФон = Theme.цвет(светлый: Theme.hex(0xFEE2E2), тёмный: Theme.hex(0xFF6168, 0.15))
    static let плохоТекст = Theme.цвет(0x991B1B, 0xFF8A8F)
    static let плохоКромка = Theme.цвет(светлый: Theme.hex(0xFECACA), тёмный: Theme.hex(0xFF6168, 0.34))
    static let инфоФон = Theme.цвет(светлый: Theme.hex(0xEEF4FF), тёмный: Theme.hex(0x60A5FA, 0.15))
    static let инфоТекст = Theme.цвет(0x1E40AF, 0x7CB8F5)
    /// --red сайта: текст причины отклонения (.adv-reason).
    static let красный = Theme.цвет(0xC0392B, 0xFF6168)
    /// Пауза в очереди (chip_paused_slot) — color:#a15a12 сайта.
    static let пауза = Theme.цвет(0xA15A12, 0xE0BD5E)
    /// --tint-ai / --on-ai / --edge-ai: фиолетовые плашки PRO и ИИ.
    static let ииФон = Theme.цвет(светлый: Theme.hex(0xF4EEFB), тёмный: Theme.hex(0xA78BFA, 0.15))
    static let ииТекст = Theme.цвет(0x6C3FC5, 0xB79BF5)
    static let ииКромка = Theme.цвет(светлый: Theme.hex(0xE5D9F5), тёмный: Theme.hex(0xA78BFA, 0.32))
    /// Кнопки «перенести» сайта: #16a34a в обеих темах.
    static let зелёнаяКнопка = Color(uiColor: Theme.hex(0x16A34A))
    static let хорошоФон = Theme.мята
    static let хорошоТекст = Theme.цвет(0x0B6B3A, 0x57D493)
    static let хорошоКромка = Theme.цвет(0xB1DFC2, 0x1F5236)
    static let индиго = Theme.цвет(0x4F46E5, 0xA5B4FC)
    static let индигоКромка = Theme.цвет(0xC7D2FE, 0x3730A3)
    static let авто = Theme.цвет(0x0369A1, 0x7DD3FC)
    static let топТекст = Color(uiColor: Theme.hex(0x5A4406))
}

/// Значок статуса (.adv-badges).
struct ЗначокОбъявления: Equatable {
    enum Вид: Equatable { case предупреждение, плохо, инфо, хорошо, серый, индиго, одобрено, пауза }
    let текст: String
    let вид: Вид
    let символ: String?
    /// Подсказка сайта (title): причина ручной проверки.
    let подсказка: String?
    /// Рамка 1.5 — у сайта не у всех значков (у «Удалено» и «На паузе» её нет).
    var кромка: Bool = true

    /// Первое подходящее условие — в том же порядке, что у сайта (карта §3.1.3).
    static func для(_ т: МоёОбъявление, вкладка: ВкладкаОбъявлений, сейчас: Double, одобрено: String) -> ЗначокОбъявления {
        let с = МоиОбъявленияText.т
        if т.ждётВерификации { return ЗначокОбъявления(текст: с("held_verify_badge"), вид: .предупреждение, символ: nil, подсказка: nil) }
        if т.статус == "approved" && !т.автоПродление && т.конецСрока > 0 && т.конецСрока <= сейчас {
            return ЗначокОбъявления(текст: с("exp_badge"), вид: .плохо, символ: nil, подсказка: nil)
        }
        if т.статус == "pending_manual" {
            let почему = т.причинаРучной.isEmpty ? с("chip_manual_why") : т.причинаРучной
            return ЗначокОбъявления(текст: с("chip_manual_review"), вид: .предупреждение, символ: "doc.text.magnifyingglass",
                                    подсказка: почему)
        }
        if (т.статус == "pending" || т.статус == "ai_check") && т.скрываемНомера {
            return ЗначокОбъявления(текст: с("chip_redacting"), вид: .инфо, символ: "checkmark.shield", подсказка: nil)
        }
        if т.статус == "pending" || т.статус == "ai_check" {
            return ЗначокОбъявления(текст: с("chip_ai_check"), вид: .инфо, символ: "hourglass", подсказка: nil)
        }
        if т.статус == "sold" {
            let услуга = РазделыСайта.услуга(т.раздел)
            return ЗначокОбъявления(текст: с(услуга ? "chip_sold_off" : "chip_sold_out"), вид: .плохо, символ: "house",
                                    подсказка: nil)
        }
        if т.статус == "inactive" && т.черновикИмпорта {
            return ЗначокОбъявления(текст: с("chip_draft_import"), вид: .индиго, символ: "square.and.arrow.down", подсказка: nil)
        }
        switch вкладка {
        case .inactive:
            if т.вОчереди > 0 {
                let текст = т.ждётСлот ? с("pq_chip_wait") : String(format: с("pq_chip"), Self.когда(т.вОчереди, сейчас: сейчас))
                return ЗначокОбъявления(текст: текст, вид: .инфо, символ: т.ждётСлот ? "hourglass" : "clock", подсказка: nil)
            }
            if т.сверхЛимита {
                return ЗначокОбъявления(текст: с(т.сверхЛимитаСамо ? "chip_held_auto" : "chip_held_slot"), вид: .инфо,
                                        символ: "clock", подсказка: nil)
            }
            if т.проданоСлот { return ЗначокОбъявления(текст: с("chip_sold_slot"), вид: .хорошо, символ: nil, подсказка: nil) }
            if т.пауза {
                return ЗначокОбъявления(текст: с("chip_paused_slot"), вид: .пауза, символ: nil, подсказка: nil, кромка: false)
            }
            return ЗначокОбъявления(текст: с("chip_inactive"), вид: .серый, символ: nil, подсказка: nil)
        case .deleted:
            return ЗначокОбъявления(текст: с("chip_deleted"), вид: .плохо, символ: nil, подсказка: nil, кромка: false)
        case .published:
            let подпись = одобрено.isEmpty ? с("approved") : одобрено
            return ЗначокОбъявления(текст: подпись, вид: .одобрено, символ: "checkmark.circle", подсказка: nil)
        }
    }

    /// _pqWhenShort: «сегодня, 14:30» / «завтра, 09:00» / «5 октября, 10:00» — по времени Алматы, как у сайта.
    static func когда(_ секунды: Double, сейчас: Double) -> String {
        let almaty = TimeZone(identifier: "Asia/Almaty") ?? TimeZone.current
        var календарь = Calendar(identifier: .gregorian)
        календарь.timeZone = almaty
        let дата = Date(timeIntervalSince1970: секунды)
        let день = календарь.startOfDay(for: дата)
        let сегодня = календарь.startOfDay(for: Date(timeIntervalSince1970: сейчас))
        let время = DateFormatter()
        время.timeZone = almaty
        время.locale = Locale(identifier: "en_GB")
        время.dateFormat = "HH:mm"
        let часы = время.string(from: дата)
        let разница = календарь.dateComponents([.day], from: сегодня, to: день).day ?? 99
        if разница == 0 { return МоиОбъявленияText.т("pq_today") + ", " + часы }
        if разница == 1 { return МоиОбъявленияText.т("pq_tomorrow") + ", " + часы }
        let числа = DateFormatter()
        числа.timeZone = almaty
        числа.locale = МоиОбъявленияText.локаль
        числа.setLocalizedDateFormatFromTemplate("dMMMM")
        return числа.string(from: дата) + ", " + часы
    }
}

/// Срок жизни объявления (advLifecycleHTML) — только у одобренных.
struct СрокОбъявления: Equatable {
    enum Вид: Equatable { case норма, скоро, срочно, авто }
    let текст: String
    let вид: Вид
    /// Доля полосы 0…1; nil — полосы нет (срок не задан или вышел).
    let полоса: Double?
    /// Вышел без авто-продления — «Не в ленте с …».
    let ушло: Bool

    static func для(_ т: МоёОбъявление, сейчас: Double) -> СрокОбъявления? {
        guard т.статус == "approved" else { return nil }
        let с = МоиОбъявленияText.т
        let конец = т.конецСрока
        if конец <= 0 { return СрокОбъявления(текст: с("life_30"), вид: .норма, полоса: nil, ушло: false) }
        if конец <= сейчас && !т.автоПродление {
            let формат = DateFormatter()
            формат.locale = МоиОбъявленияText.локаль
            формат.setLocalizedDateFormatFromTemplate("dMMMM")
            let дата = формат.string(from: Date(timeIntervalSince1970: конец))
            return СрокОбъявления(текст: String(format: с("life_gone"), дата), вид: .срочно, полоса: nil, ушло: true)
        }
        let дней = max(0, Int(((конец - сейчас) / 86_400).rounded(.up)))
        let процент = max(3.0, min(100.0, ((конец - сейчас) / 2_592_000 * 100).rounded()))
        if т.автоПродление {
            return СрокОбъявления(текст: String(format: с("adv_autorenew_in"), дней), вид: .авто, полоса: процент / 100,
                                  ушло: false)
        }
        let вид: Вид = дней <= 2 ? .срочно : (дней <= 7 ? .скоро : .норма)
        let текст = дней > 0 ? String(format: с("adv_active_left"), дней) : с("adv_expires_today")
        return СрокОбъявления(текст: текст, вид: вид, полоса: процент / 100, ушло: false)
    }
}

// MARK: - Карточка

struct КарточкаМоегоОбъявления: View {
    let товар: МоёОбъявление
    let вкладка: ВкладкаОбъявлений
    /// IS_SHOP страницы кабинета — склад на карточке.
    let магазин: Bool
    /// ADV_STATUS_LABEL страницы кабинета.
    let подписьОдобрено: String
    let занято: Bool
    let проверяем: Bool
    let действие: (ДействиеКарточки) -> Void
    let скопироватьID: () -> Void
    /// Режим «Выбрать»: ряда кнопок нет (.advsel-mode .adv-acts{display:none} сайта).
    let режимВыбора: Bool

    /// Открытый список «кто» (like / msg / call / share) — как #adv-who-<id> сайта.
    @State private var кто: String? = nil

    /// Свой init: с @State private поэлементный init стал бы private.
    init(товар: МоёОбъявление, вкладка: ВкладкаОбъявлений, магазин: Bool, подписьОдобрено: String, занято: Bool,
         проверяем: Bool, действие: @escaping (ДействиеКарточки) -> Void, скопироватьID: @escaping () -> Void,
         режимВыбора: Bool = false) {
        self.товар = товар
        self.вкладка = вкладка
        self.магазин = магазин
        self.подписьОдобрено = подписьОдобрено
        self.занято = занято
        self.проверяем = проверяем
        self.действие = действие
        self.скопироватьID = скопироватьID
        self.режимВыбора = режимВыбора
    }

    private var сейчас: Double { Date().timeIntervalSince1970 }
    private func т(_ ключ: String) -> String { МоиОбъявленияText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            верх
            низ
        }
        .padding(14)
        .background {
            фонКарточки
                .shadow(color: товар.топ ? Self.топСвечение : .clear, radius: 10, y: 10)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(товар.топ ? Self.топКромка : Theme.линия, lineWidth: 1)
        }
        .opacity(занято ? 0.7 : 1)
    }

    /// .adv-card.top-premium: золотая кромка, тёплая заливка сверху и полоса 4 пт у начала карточки.
    private static let топКромка = Theme.цвет(0xE4C579, 0x6D5926)
    private static let топЗаливка = Theme.цвет(0xFFFDF5, 0x221D10)
    private static let топСвечение = Color(uiColor: Theme.hex(0xB08418, 0.5))
    private static let топПолоса = LinearGradient(colors: [Color(uiColor: Theme.hex(0xF4D982)),
                                                          Color(uiColor: Theme.hex(0xD3A02B))],
                                                 startPoint: .top, endPoint: .bottom)

    @ViewBuilder
    private var фонКарточки: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
        if товар.топ {
            ZStack(alignment: .leading) {
                LinearGradient(colors: [Self.топЗаливка, Theme.поверхность], startPoint: .top, endPoint: .bottom)
                Rectangle()
                    .fill(Self.топПолоса)
                    .frame(width: 4)
            }
            .clipShape(форма)
        } else {
            форма.fill(Theme.поверхность)
        }
    }

    // MARK: Верх: фото и сведения

    private var верх: some View {
        HStack(alignment: .top, spacing: 12) {
            Button { действие(.открыть) } label: { фото }
                .buttonStyle(.plain)
                .accessibilityLabel(String(format: т("a11y_photo"), товар.название))
            VStack(alignment: .leading, spacing: 4) {
                цена
                Button { действие(.открыть) } label: { название }
                    .buttonStyle(.plain)
                    .accessibilityHint(т("adv_open"))
                мета
                значок
                if вкладка != .deleted {
                    СчётчикиОбъявления(статистика: товар.статистика, открыто: $кто, ждут: { действие(.ждут) })
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var фото: some View {
        КартинкаЛенты(Config.url(товар.фото), пунктов: 96) {
            ZStack {
                Theme.мята
                Image(systemName: "shippingbox")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.текстВторой)
            }
        }
        .frame(width: 96, height: 84)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
    }

    /// advPriceHTML: «{цена} ₸ · Торг», «Договорная», аренда «{цена} ₸/сут» и « · продажа {цена} ₸».
    private var цена: some View {
        let суффикс = суффиксЦены
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(основнаяЦена)
                .font(.system(size: 16, weight: .heavy))
                .tracking(-0.2)
                .foregroundStyle(Theme.текст)
            if !суффикс.isEmpty {
                Text(суффикс)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.текстВторой)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityElement(children: .combine)
    }

    private var основнаяЦена: String {
        if товар.аренда && товар.ценаАренды > 0 { return (DesignText.число(Int(товар.ценаАренды)) + "\u{00A0}₸").слеваНаправо }
        if товар.цена > 0 { return (DesignText.число(Int(товар.цена)) + "\u{00A0}₸").слеваНаправо }
        return т("price_negotiable")
    }

    private var суффиксЦены: String {
        if товар.аренда && товар.ценаАренды > 0 {
            var с = "/" + т(товар.периодАренды == "month" ? "unit_month" : "unit_day")
            if товар.цена > 0 { с += " · " + т("adv_sale") + " " + DesignText.число(Int(товар.цена)) + "\u{00A0}₸" }
            return с
        }
        if товар.цена > 0 && товар.торг { return " · " + т("torg") }
        return ""
    }

    private var название: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(товар.название)
                .font(.system(size: 14, weight: .bold))
                .lineSpacing(2)
                .foregroundStyle(Theme.текст)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
            if товар.топ { ЗначокТоп() }
        }
    }

    /// Дата как её прислал сервер и #номер с копированием (advCopyId).
    private var мета: some View {
        HStack(spacing: 6) {
            Text(товар.создано)
                .lineLimit(1)
            Button(action: скопироватьID) {
                HStack(spacing: 3) {
                    Text("#" + товар.id)
                        .lineLimit(1)
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(т("adv_id_copy") + ", #" + товар.id)
        }
        .font(.system(size: 12))
        .foregroundStyle(Theme.текстВторой)
    }

    private var значок: some View {
        ЯрлыкСтатуса(значок: ЗначокОбъявления.для(товар, вкладка: вкладка, сейчас: сейчас, одобрено: подписьОдобрено))
    }

    // MARK: Низ: блоки и кнопки

    private var низ: some View {
        VStack(alignment: .leading, spacing: 8) {
            if товар.ждётВерификации { блокВерификации }
            if товар.статус == "pending_manual" {
                БлокКарточки(текст: т("manual_body"), символ: "doc.text.magnifyingglass",
                             фон: КраскаОбъявлений.предупреждениеФон, цвет: КраскаОбъявлений.предупреждениеТекст)
            }
            if товар.статус == "rejected" && !товар.причина.isEmpty { блокПричины }
            if товар.статус == "deleted_permanent" {
                БлокКарточки(текст: т("blocked_body"), символ: "nosign",
                             фон: КраскаОбъявлений.плохоФон, цвет: КраскаОбъявлений.плохоТекст)
            }
            if товар.топ && !товар.топДо.isEmpty { топДо }
            if вкладка == .published && товар.статус == "approved" && товар.следующееПоднятие > сейчас { поднятия }
            if let срок = СрокОбъявления.для(товар, сейчас: сейчас) {
                СрокКарточки(срок: срок, включено: товар.автоПродление, занято: занято) { новое in
                    действие(.автоПродление(новое))
                }
            }
            if складВиден {
                СкладКарточки(остаток: товар.склад, продано: товар.статус == "sold", занято: занято) { количество in
                    действие(.склад(количество))
                }
                .id(товар.id + ":" + String(товар.склад) + ":" + товар.статус)
            }
            if let ключ = кто {
                СписокКто(ключ: ключ, записи: товар.статистика.кто[ключ] ?? [])
            }
            if !режимВыбора { кнопки }
        }
    }

    private var блокВерификации: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 14))
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(т("held_verify_t")).bold()
                Text(т("held_verify_s"))
            }
            .font(.system(size: 12))
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { действие(.верификация) } label: {
                Text(т("held_verify_go"))
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(КраскаОбъявлений.предупреждениеТекст,
                                in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
            .fixedSize()
            .frame(maxHeight: .infinity)
        }
        .foregroundStyle(КраскаОбъявлений.предупреждениеТекст)
        .padding(12)
        .background(КраскаОбъявлений.предупреждениеФон, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(КраскаОбъявлений.предупреждениеКромка, lineWidth: 1.5)
        }
    }

    private var блокПричины: some View {
        var текст = String(format: т("reason"), товар.причина)
        if товар.отклонений > 1 { текст += " " + String(format: т("attempt"), товар.отклонений) }
        return БлокКарточки(текст: текст, символ: "xmark.circle", фон: КраскаОбъявлений.плохоФон,
                            цвет: КраскаОбъявлений.красный)
    }

    /// «В ТОПе до YYYY-MM-DD» — top_until.slice(0,10), как у сайта. Только сведения: продлевают ТОП на сайте.
    private var топДо: some View {
        Label {
            Text(String(format: т("adv_top_until"), String(товар.топДо.prefix(10))))
        } icon: {
            Image(systemName: "crown")
                .font(.system(size: 11))
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(Theme.цвет(0xA9791A, 0xD8B658))
    }

    /// «Бесплатные авто-поднятия (день 7·14·21) — включены · следующее через N дн.» — сведения из окна продвижения сайта
    /// (сам ТОП и платные поднятия в приложении не продаются).
    private var поднятия: some View {
        let дней = max(0, Int(((товар.следующееПоднятие - сейчас) / 86_400).rounded(.up)))
        return Text(т("promo_free_bumps") + " · " + String(format: т("promo_next_in"), дней))
            .font(.system(size: 12))
            .foregroundStyle(Theme.текстВторой)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// advStockHTML: только магазин и не услуги, работа, недвижимость, транспорт (кроме автозапчастей). Раздел —
    /// category объявления как есть (catResolve сайта сводит старые названия к нынешним — INFERRED, что их нет в ответе).
    private var складВиден: Bool {
        guard магазин else { return false }
        let корень = РазделыСайта.корень(товар.раздел)
        if корень == "services" || корень == "jobs" || корень == "realty" { return false }
        if корень == "transport" { return РазделыСайта.внутри(товар.раздел, ["auto-parts"]) }
        return true
    }

    private var кнопки: some View {
        let набор = КнопкаОбъявления.набор(товар, вкладка: вкладка)
        // .adv-acts: всегда две равные колонки, зазор 6; margin-top 10 = 8 от стопки + 2.
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)],
                         alignment: .leading, spacing: 6) {
            ForEach(набор, id: \.self) { кнопка in
                КнопкаКарточки(подпись: кнопка.подпись(топ: товар.топ), значок: кнопка.значок, вид: вид(кнопка)) {
                    действие(.кнопка(кнопка))
                }
                .disabled(занято || (кнопка == .проверить && проверяем))
            }
        }
        .padding(.top, 2)
    }

    private func вид(_ кнопка: КнопкаОбъявления) -> КнопкаКарточки.Вид {
        switch кнопка {
        case .активировать, .восстановить, .проверить: return .вперёд
        case .удалить, .удалитьНавсегда:               return .удалить
        case .поделиться:                              return .поделиться
        case .продвинуть:                              return товар.топ ? .топ : .вперёд
        default:                                       return .обычная
        }
    }
}

// MARK: - Части карточки

/// Значок «ТОП» рядом с названием (.adv-top-badge): золото, корона.
struct ЗначокТоп: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "crown.fill")
                .font(.system(size: 9, weight: .bold))
            Text(МоиОбъявленияText.т("adv_top"))
                .font(.system(size: 10, weight: .heavy))
        }
        .foregroundStyle(КраскаОбъявлений.топТекст)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(LinearGradient(colors: [Theme.топНачало, Theme.топКонец], startPoint: .topLeading,
                                   endPoint: .bottomTrailing), in: Capsule())
        .fixedSize()
    }
}

/// Значок статуса — плашка со скруглением 6, как span-значки сайта; «Опубликовано» — капсула .badge-approved.
struct ЯрлыкСтатуса: View {
    let значок: ЗначокОбъявления

    private var одобрено: Bool { значок.вид == .одобрено }

    var body: some View {
        HStack(spacing: 4) {
            if let символ = значок.символ {
                Image(systemName: символ)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(одобрено ? Theme.цвет(0x12A05A, 0x57D493) : цвет)
                    .accessibilityHidden(true)
            }
            Text(значок.текст)
                .font(.system(size: 11, weight: .bold))
                .tracking(одобрено ? 0.22 : 0)
                .lineLimit(2)
        }
        .foregroundStyle(цвет)
        .padding(.horizontal, одобрено ? 12 : 8)
        .padding(.vertical, одобрено ? 4 : 2)
        .background { форма.fill(фон) }
        .overlay {
            if значок.кромка {
                форма.strokeBorder(кромка, lineWidth: одобрено ? 1 : 1.5)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(значок.подсказка ?? "")
    }

    private var форма: RoundedRectangle {
        RoundedRectangle(cornerRadius: одобрено ? 100 : Theme.Радиус.xxs, style: .continuous)
    }

    private var цвет: Color {
        switch значок.вид {
        case .предупреждение: return КраскаОбъявлений.предупреждениеТекст
        case .плохо:          return КраскаОбъявлений.плохоТекст
        case .инфо:           return КраскаОбъявлений.инфоТекст
        case .хорошо, .одобрено: return КраскаОбъявлений.хорошоТекст
        case .серый:          return Theme.текстВторой
        case .индиго:         return КраскаОбъявлений.индиго
        case .пауза:          return КраскаОбъявлений.пауза
        }
    }

    private var фон: Color {
        switch значок.вид {
        case .предупреждение, .пауза: return КраскаОбъявлений.предупреждениеФон
        case .плохо:          return КраскаОбъявлений.плохоФон
        case .инфо, .индиго:  return КраскаОбъявлений.инфоФон
        case .хорошо:         return КраскаОбъявлений.хорошоФон
        case .одобрено:       return Theme.цвет(0xE7F6EE, 0x12301F)
        case .серый:          return Theme.поверхность2
        }
    }

    private var кромка: Color {
        switch значок.вид {
        case .предупреждение: return КраскаОбъявлений.предупреждениеКромка
        case .плохо:          return КраскаОбъявлений.плохоКромка
        case .одобрено:       return КраскаОбъявлений.хорошоКромка
        case .индиго:         return КраскаОбъявлений.индигоКромка
        case .инфо, .хорошо, .серый, .пауза: return Color.clear
        }
    }
}

/// Блок в теле карточки (.adv-reason): значок и текст на цветной подложке.
struct БлокКарточки: View {
    let текст: String
    let символ: String
    let фон: Color
    let цвет: Color

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: символ)
                .font(.system(size: 13, weight: .semibold))
                .padding(.top, 1)
                .accessibilityHidden(true)
            Text(текст)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(цвет)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(фон, in: RoundedRectangle(cornerRadius: Theme.Радиус.xxs, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Кнопка ряда .adv-acts: рамка, значок и подпись; «вперёд» — зелёная, «удалить» — красная.
struct КнопкаКарточки: View {
    enum Вид { case обычная, вперёд, удалить, топ, поделиться }
    let подпись: String
    let значок: String
    let вид: Вид
    let нажать: () -> Void

    var body: some View {
        Button(action: нажать) {
            HStack(spacing: 6) {
                Image(systemName: значок)
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityHidden(true)
                Text(подпись)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(цвет)
            .frame(maxWidth: .infinity, minHeight: 34)
            .padding(.horizontal, 10)
            .background(фон, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                    .strokeBorder(Theme.линия, lineWidth: 1)
            }
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
    }

    private var цвет: Color {
        switch вид {
        case .обычная: return Theme.текст
        case .вперёд, .поделиться: return Theme.акцент
        case .удалить: return КраскаОбъявлений.плохоТекст
        case .топ:     return Theme.золото
        }
    }

    private var фон: Color {
        switch вид {
        case .топ: return Theme.топФон
        case .поделиться: return Theme.оттенокАкцента
        case .обычная, .вперёд, .удалить: return Theme.поверхность
        }
    }
}

/// Счётчики .adv-stats: просмотры, избранное, сообщения, звонки, поделились, «Ждут появления». Нули — серые; нажатие
/// на ненулевой (кроме просмотров) раскрывает список «кто».
struct СчётчикиОбъявления: View {
    let статистика: СтатистикаОбъявления
    @Binding var открыто: String?
    let ждут: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            счётчик("eye", число: статистика.просмотры, ключ: nil, подпись: "views")
            счётчик("heart", число: статистика.избранное, ключ: "like", подпись: "likes")
            счётчик("bubble.left", число: статистика.сообщения, ключ: "msg", подпись: "msgs")
            счётчик("phone", число: статистика.звонки, ключ: "call", подпись: "calls")
            счётчик("square.and.arrow.up", число: статистика.поделились, ключ: "share", подпись: "shares")
            if статистика.ждут > 0 {
                Button(action: ждут) {
                    метка("hand.raised", число: статистика.ждут, активен: true, ждут: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(format: МоиОбъявленияText.т("a11y_stat"), МоиОбъявленияText.т("wl_pill"),
                                           статистика.ждут))
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func счётчик(_ символ: String, число: Int, ключ: String?, подпись: String) -> some View {
        let текст = String(format: МоиОбъявленияText.т("a11y_stat"), МоиОбъявленияText.т(подпись), число)
        if let ключ, число > 0 {
            Button {
                открыто = открыто == ключ ? nil : ключ
            } label: {
                метка(символ, число: число, активен: открыто == ключ)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(текст)
            .accessibilityAddTraits(открыто == ключ ? .isSelected : [])
        } else {
            метка(символ, число: число, активен: false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(текст)
        }
    }

    /// .adv-stat: значок 14 цвета #b6c0ba (в обеих темах), число 12 жирное серое; ноль — вся метка 0.55;
    /// открытый список «кто» и «Ждут» — акцент.
    private func метка(_ символ: String, число: Int, активен: Bool, ждут: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: символ)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(активен ? Theme.акцент : Self.цветЗначка)
            Text(String(число))
                .font(.system(size: 12, weight: ждут ? .heavy : .bold))
                .monospacedDigit()
                .foregroundStyle(активен ? Theme.акцент : Theme.текстВторой)
        }
        .opacity(число > 0 ? 1 : 0.55)
    }

    private static let цветЗначка = Color(uiColor: Theme.hex(0xB6C0BA))
}

/// Список «кто» (advWhoToggle): заголовок, строки «буква · имя · когда», пусто — фраза сайта.
struct СписокКто: View {
    let ключ: String
    let записи: [КтоОбъявления]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(заголовок)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.текст)
                .accessibilityAddTraits(.isHeader)
            if записи.isEmpty {
                Text(МоиОбъявленияText.т("who_empty"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(записи.enumerated()), id: \.offset) { пара in
                    строка(пара.element)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
    }

    private var заголовок: String {
        let подпись: String
        switch ключ {
        case "like": подпись = МоиОбъявленияText.т("likes")
        case "msg":  подпись = МоиОбъявленияText.т("msgs")
        case "call": подпись = МоиОбъявленияText.т("calls")
        default:     подпись = МоиОбъявленияText.т("shares")
        }
        return записи.isEmpty ? подпись : подпись + " · " + String(записи.count)
    }

    private func строка(_ запись: КтоОбъявления) -> some View {
        let имя = запись.имя.trimmingCharacters(in: .whitespaces).isEmpty ? МоиОбъявленияText.т("guest") : запись.имя
        let буква = String(имя.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
        return HStack(spacing: 8) {
            Text(буква.isEmpty ? "?" : буква)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.акцент)
                .frame(width: 26, height: 26)
                .background(Theme.мята, in: Circle())
                .accessibilityHidden(true)
            Text(имя)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.текст)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(запись.когда)
                .font(.system(size: 11))
                .foregroundStyle(Theme.текстВторой)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Срок жизни и переключатель «Авто-продление» (.adv-lifecycle).
struct СрокКарточки: View {
    let срок: СрокОбъявления
    let включено: Bool
    let занято: Bool
    let переключить: (Bool) -> Void

    var body: some View {
        // .adv-lifecycle: срок с полосой и чип авто-продления в ряд; не влезает (SE, kk/ar) — чип строкой ниже.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                срокСПолосой
                чипПродления
            }
            VStack(alignment: .leading, spacing: 10) {
                срокСПолосой
                чипПродления
            }
        }
        .padding(.top, 2)
        .opacity(срок.ушло ? 0.85 : 1)
    }

    private var срокСПолосой: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(срок.текст)
            } icon: {
                Image(systemName: "clock")
            }
            .labelStyle(МеткаСрока())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(цвет)
            if let доля = срок.полоса {
                GeometryReader { гео in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.поверхность2)
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(цветПолосы)
                            .frame(width: max(6, гео.size.width * CGFloat(доля)))
                    }
                }
                .frame(height: 6)
                .accessibilityHidden(true)
            }
        }
        .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
    }

    /// .adv-renew: чип-кнопка с маленьким переключателем 32×18, включено — акцентная рамка и заливка.
    private var чипПродления: some View {
        Button { переключить(!включено) } label: {
            HStack(spacing: 8) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(включено ? Theme.акцент : Self.выключено)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 14, height: 14)
                        .offset(x: включено ? 16 : 2)
                }
                .frame(width: 32, height: 18)
                .environment(\.layoutDirection, .leftToRight)
                .animation(.easeOut(duration: 0.2), value: включено)
                Text(МоиОбъявленияText.т("adv_autorenew"))
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(включено ? Theme.акцент : Theme.текстВторой)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(включено ? Theme.оттенокАкцента : Theme.поверхность,
                        in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                    .strokeBorder(включено ? Theme.акцент : Theme.линия, lineWidth: 1.5)
            }
            .fixedSize()
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
        .disabled(занято)
        .accessibilityRepresentation {
            Toggle(МоиОбъявленияText.т("adv_autorenew"), isOn: Binding(get: { включено }, set: { новое in переключить(новое) }))
        }
        .accessibilityHint(МоиОбъявленияText.т("autorenew_hint"))
    }

    private static let выключено = Theme.цвет(светлый: Theme.hex(0xCBD5D1), тёмный: Theme.hex(0xFFFFFF, 0.24))

    private var цвет: Color {
        switch срок.вид {
        case .норма:  return Theme.текстВторой
        case .скоро:  return КраскаОбъявлений.предупреждениеТекст
        case .срочно: return КраскаОбъявлений.плохоТекст
        case .авто:   return КраскаОбъявлений.авто
        }
    }

    /// .al-bar i: норма — зелёный к акценту, скоро — #d97706→#f59e0b, срочно — #dc2626, авто — #0ea5e9→акцент.
    private var цветПолосы: LinearGradient {
        let цвета: [Color]
        switch срок.вид {
        case .норма:  цвета = [Theme.зелёный, Theme.акцент]
        case .скоро:  цвета = [Theme.оранжевый, Color(uiColor: Theme.hex(0xF59E0B))]
        case .срочно: цвета = [Theme.ценаСкидка, Theme.ценаСкидка]
        case .авто:   цвета = [Color(uiColor: Theme.hex(0x0EA5E9)), Theme.акцент]
        }
        return LinearGradient(colors: цвета, startPoint: .leading, endPoint: .trailing)
    }
}

/// Значок и текст срока с зазором 6, как .al-txt сайта.
private struct МеткаСрока: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
            configuration.title
        }
    }
}

/// Склад магазина (.adv-stock): «На складе», «−» / поле / «+», «шт», «Сохранить» — только когда число изменено.
struct СкладКарточки: View {
    let остаток: Int
    let продано: Bool
    let занято: Bool
    let сохранить: (Int) -> Void

    @State private var поле: String = ""

    init(остаток: Int, продано: Bool, занято: Bool, сохранить: @escaping (Int) -> Void) {
        self.остаток = остаток
        self.продано = продано
        self.занято = занято
        self.сохранить = сохранить
        _поле = State(initialValue: String(остаток))
    }

    private var число: Int? {
        guard let n = Int(поле.trimmingCharacters(in: .whitespaces)), n >= 0 else { return nil }
        return n
    }

    private var изменено: Bool {
        guard let n = число else { return false }
        return n != остаток
    }

    private var неВедётся: Bool { остаток <= 0 && !продано }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(МоиОбъявленияText.т("stock_lbl"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.текст)
                if продано {
                    Text(МоиОбъявленияText.т("stock_out"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(КраскаОбъявлений.плохоТекст)
                } else if неВедётся {
                    Text(МоиОбъявленияText.т("stock_none"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.текстВторой)
                }
            }
            HStack(spacing: 8) {
                шаг(-1, подпись: "−", доступность: МоиОбъявленияText.т("stock_minus"))
                TextField("0", text: $поле)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 15, weight: .bold))
                    .monospacedDigit()
                    .frame(width: 64, height: 34)
                    .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous))
                    .accessibilityLabel(МоиОбъявленияText.т("stock_lbl"))
                    .onSubmit { сохранитьЕсли() }
                шаг(1, подпись: "+", доступность: МоиОбъявленияText.т("stock_plus"))
                Text(МоиОбъявленияText.т("stock_unit"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
                Spacer(minLength: 4)
                if изменено {
                    Button(МоиОбъявленияText.т("stock_save")) { сохранитьЕсли() }
                        .font(.system(size: 13, weight: .bold))
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.зелёный)
                        .controlSize(.small)
                        .disabled(занято)
                }
            }
            Text(МоиОбъявленияText.т(неВедётся ? "stock_hint_none" : "stock_hint"))
                .font(.system(size: 11))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            LinearGradient(colors: продано ? [Self.нетВерх, Theme.поверхность] : [Self.складВерх, Theme.поверхность],
                           startPoint: .top, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                .strokeBorder(продано ? Self.нетКромка : Theme.линия, lineWidth: 1)
        }
    }

    /// .adv-stock: сверху --surf2 (тёмная — акцент 0.09), вниз к карточке; .out — розовый.
    private static let складВерх = Theme.цвет(светлый: Theme.hex(0xF6FAF8), тёмный: Theme.hex(0x34C997, 0.09))
    private static let нетВерх = Theme.цвет(0xFFF5F5, 0x2A1414)
    private static let нетКромка = Theme.цвет(0xFBCFCF, 0x5B2B2B)

    private func шаг(_ на: Int, подпись: String, доступность: String) -> some View {
        Button {
            let было = число ?? 0
            поле = String(max(0, было + на))
        } label: {
            Text(подпись)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.текст)
                .frame(width: 34, height: 34)
                .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous)
                        .strokeBorder(Theme.линия, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(занято)
        .accessibilityLabel(доступность)
    }

    /// stockSave сайта: не число или меньше нуля — «Введите число ≥ 0» (скажет модель), иначе stock_adjust.
    private func сохранитьЕсли() {
        guard изменено || число == nil else { return }
        сохранить(число ?? -1)
    }
}
