import EventKit
import EventKitUI
import SwiftUI
import UIKit

/**
 «НАПОМНИТЬ» В ОКНЕ «ЗВОНОК — В РАБОЧЕЕ ВРЕМЯ» (mkHoursGateModal → mkHoursRemind сайта; владелец: «на сайт не прыгать»).

 Сайт собирает ссылку /ics.php?s=<начало>&e=<конец>&t=<заголовок>&u=<адрес объявления>&d=<описание>&id=<номер> и на
 iPhone уходит по ней (файл .ics → системное «Добавить в календарь»), затем тост «Напоминание сохранено в календарь»:
   · начало — mkHoursNextOpen: сейчас плюс минуты до открытия по времени сайта (UTC+5, MK_HOURS_TZ_OFFSET = 300);
   · конец — начало плюс 15 минут;
   · заголовок — hours_ics_sum «Позвонить продавцу: {t}» (название без переводов строк, запятых и точек с запятой);
   · описание — hours_ics_desc, адрес — mkItemUrl (канонический адрес объявления).
 Здесь те же поля — системным окном события EventKitUI (EKEventEditViewController) с напоминанием в момент начала:
 человек видит событие и жмёт «Добавить», страницы и файла нет. С iOS 17 это окно работает вне процесса приложения и
 доступа к календарю не требует, поэтому вопроса о разрешении нет (строки NSCalendars… в project.yml — на случай, если
 система всё же спросит). Места (LOCATION) сайт в ics.php не передаёт — поле пустое; ссылка на объявление — и в поле
 адреса, и в заметке.
 */
struct НапоминаниеЗвонка: Equatable {
    let заголовок: String
    let начало: Date
    let конец: Date
    let адрес: URL?
    let описание: String
    /// Минут до открытия — «откроется через …» (mkHoursUntilText).
    let минутДоОткрытия: Int

    /// nil — у объявления нет окна часов («range») или продавец сейчас на месте (_mkMinUntilOpen = 0).
    init?(товар: Listing, сейчас: Date = Date()) {
        guard товар.часыРежим == "range", let с = Self.минуты(товар.часыС), let до = Self.минуты(товар.часыДо),
              с != до else { return nil }
        var календарь = Calendar(identifier: .gregorian)
        календарь.timeZone = TimeZone(secondsFromGMT: 5 * 3600) ?? .current
        let теперь = календарь.component(.hour, from: сейчас) * 60 + календарь.component(.minute, from: сейчас)
        let открыто = с < до ? (теперь >= с && теперь < до) : (теперь >= с || теперь < до)
        guard !открыто else { return nil }
        var минут = с - теперь
        if минут <= 0 { минут += 1440 }
        /* Начало минуты: пояс сайта — целые часы от UTC, границы минут те же. */
        let минута = (сейчас.timeIntervalSince1970 / 60).rounded(.down) * 60
        let начало = Date(timeIntervalSince1970: минута + Double(минут) * 60)
        /* String(e.title).replace(/[\r\n,;]/g, " "). */
        let название = String(товар.title.map { знак -> Character in
            (знак.isNewline || знак == "," || знак == ";") ? " " : знак
        })
        заголовок = ТекстыНапоминания.т("hours_ics_sum").replacingOccurrences(of: "{t}", with: название)
        self.начало = начало
        конец = начало.addingTimeInterval(900)
        адрес = товар.адрес
        описание = ТекстыНапоминания.т("hours_ics_desc")
        минутДоОткрытия = минут
    }

    /// «09:30» → 570 (_hm2m сайта).
    private static func минуты(_ строка: String?) -> Int? {
        guard let части = строка?.split(separator: ":"), let ч = части.first.flatMap({ Int($0) }) else { return nil }
        let м = части.count > 1 ? (Int(части[1]) ?? 0) : 0
        return ч * 60 + м
    }

    /// Заметка события: описание сайта и ссылка на объявление.
    var заметка: String {
        guard let адрес else { return описание }
        return описание + "\n\n" + адрес.absoluteString
    }
}

extension НапоминаниеЗвонка {
    /**
     Сама ссылка сайта /ics.php?s=<unix>&e=<unix>&t=&u=&d=&id= (mkHoursRemind) — из текста, пуша или другой страницы: те
     же поля события. nil — не эта страница или без начала. Путь — от корня или с /kz/<язык>/ впереди.
     */
    init?(ссылка: URL) {
        guard ссылка.lastPathComponent.lowercased() == "ics.php",
              let части = URLComponents(url: ссылка.absoluteURL, resolvingAgainstBaseURL: true) else { return nil }
        let поля = части.queryItems ?? []
        func значение(_ имя: String) -> String {
            (поля.first(where: { $0.name == имя })?.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let с = Double(значение("s")), с.isFinite, с > 0 else { return nil }
        let до = Double(значение("e")) ?? 0
        let начало = Date(timeIntervalSince1970: с)
        let заголовокСсылки = значение("t")
        let адресСсылки = значение("u")
        заголовок = заголовокСсылки.isEmpty ? ТекстыНапоминания.т("hours_remind") : заголовокСсылки
        self.начало = начало
        конец = до.isFinite && до > с ? Date(timeIntervalSince1970: до) : начало.addingTimeInterval(900)
        адрес = адресСсылки.isEmpty ? nil : Config.url(адресСсылки)
        описание = значение("d")
        let осталось = (с - Date().timeIntervalSince1970) / 60
        минутДоОткрытия = осталось > 0 && осталось < 100_000 ? Int(осталось.rounded(.up)) : 0
    }
}

/// Чем кончилось окно события.
enum ИтогКалендаряЗвонка {
    case добавлено
    case отменено
    /// Окно не встало (что-то ещё уезжало с экрана дольше 3 с).
    case неВышло
}

@MainActor
enum КалендарьНапоминаний {
    /// Делегат окна события живёт, пока окно на экране (editViewDelegate — слабая ссылка).
    private static var делегат: ДелегатКалендаряЗвонка?

    /// Системное окно события поверх верхнего экрана; готово — когда его закрыли.
    static func добавить(_ напоминание: НапоминаниеЗвонка, готово: @escaping (ИтогКалендаряЗвонка) -> Void) {
        Task { @MainActor in
            for _ in 0..<12 {
                if let верх = ПоверхВсего.верхний() {
                    КалендарьНапоминаний.показать(напоминание, над: верх, готово: готово)
                    return
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            готово(.неВышло)
        }
    }

    private static func показать(_ н: НапоминаниеЗвонка, над верх: UIViewController,
                                 готово: @escaping (ИтогКалендаряЗвонка) -> Void) {
        let хранилище = EKEventStore()
        let событие = EKEvent(eventStore: хранилище)
        событие.title = н.заголовок
        событие.startDate = н.начало
        событие.endDate = н.конец
        событие.url = н.адрес
        событие.notes = н.заметка
        /* «Напомнить» — оповещение в момент открытия, как напоминание файла сайта. */
        событие.addAlarm(EKAlarm(relativeOffset: 0))
        let окно = EKEventEditViewController()
        окно.eventStore = хранилище
        окно.event = событие
        let посредник = ДелегатКалендаряЗвонка { добавлено in
            КалендарьНапоминаний.делегат = nil
            готово(добавлено ? .добавлено : .отменено)
        }
        делегат = посредник
        окно.editViewDelegate = посредник
        верх.present(окно, animated: true)
    }
}

/// Делегат EKEventEditViewController: закрыть окно и сказать, добавлено ли событие.
final class ДелегатКалендаряЗвонка: NSObject, EKEventEditViewDelegate {
    private let конец: (Bool) -> Void

    init(конец: @escaping (Bool) -> Void) {
        self.конец = конец
    }

    func eventEditViewController(_ controller: EKEventEditViewController,
                                 didCompleteWith action: EKEventEditViewAction) {
        let добавлено = action == .saved
        let конец = self.конец
        MainActor.assumeIsolated {
            controller.dismiss(animated: true)
            конец(добавлено)
        }
    }
}

// MARK: - Тексты

/**
 Русские — словарь сайта js/i18n-marketplace-ru.js (hours_remind, hours_remind_hint, hours_remind_set, hours_ics_sum,
 hours_ics_desc, hours_opens_in, hours_u_h, hours_u_m); remind_fail — своё. Остальные языки — перевод тех же фраз.
 */
enum ТекстыНапоминания {
    static func т(_ ключ: String) -> String {
        let словарь = тексты[ListingPageText.язык] ?? тексты["ru"] ?? [:]
        return словарь[ключ] ?? тексты["ru"]?[ключ] ?? ключ
    }

    /// mkHoursUntilText: «откроется через 2 ч 15 мин», «через 40 мин»; 0 — пусто.
    static func черезСколько(_ минут: Int) -> String {
        guard минут >= 1 else { return "" }
        let часы = минут / 60
        let остаток = минут % 60
        var срок = String(остаток) + " " + т("hours_u_m")
        if часы > 0 {
            срок = String(часы) + " " + т("hours_u_h")
            if остаток > 0 { срок += " " + String(остаток) + " " + т("hours_u_m") }
        }
        return т("hours_opens_in").replacingOccurrences(of: "{t}", with: срок)
    }

    private static let тексты: [String: [String: String]] = [
        "ru": [
            "hours_remind": "Напомнить",
            "hours_remind_hint": "В календарь добавится напоминание со ссылкой на это объявление — на время открытия.",
            "hours_remind_set": "Напоминание сохранено в календарь",
            "hours_ics_sum": "Позвонить продавцу: {t}",
            "hours_ics_desc": "Продавец принимает звонки в это удобное ему время.",
            "hours_opens_in": "откроется через {t}", "hours_u_h": "ч", "hours_u_m": "мин",
            "remind_fail": "Не получилось открыть календарь. Попробуйте ещё раз"
        ],
        "kk": [
            "hours_remind": "Еске салу",
            "hours_remind_hint": "Күнтізбеге осы хабарландыруға сілтемесі бар еске салғыш қосылады — ашылу уақытына.",
            "hours_remind_set": "Еске салғыш күнтізбеге сақталды",
            "hours_ics_sum": "Сатушыға қоңырау шалу: {t}",
            "hours_ics_desc": "Сатушы қоңырауларды өзіне ыңғайлы осы уақытта қабылдайды.",
            "hours_opens_in": "{t} кейін ашылады", "hours_u_h": "сағ", "hours_u_m": "мин",
            "remind_fail": "Күнтізбені ашу мүмкін болмады. Қайталап көріңіз"
        ],
        "en": [
            "hours_remind": "Remind me",
            "hours_remind_hint": "A reminder with a link to this listing will be added to your calendar — for the opening time.",
            "hours_remind_set": "Reminder saved to your calendar",
            "hours_ics_sum": "Call the seller: {t}",
            "hours_ics_desc": "The seller takes calls at this time that suits them.",
            "hours_opens_in": "opens in {t}", "hours_u_h": "h", "hours_u_m": "min",
            "remind_fail": "Couldn't open the calendar. Please try again"
        ],
        "ar": [
            "hours_remind": "ذكّرني",
            "hours_remind_hint": "سيُضاف إلى التقويم تذكير برابط هذا الإعلان — في وقت بدء الاستقبال.",
            "hours_remind_set": "تم حفظ التذكير في التقويم",
            "hours_ics_sum": "الاتصال بالبائع: {t}",
            "hours_ics_desc": "يستقبل البائع المكالمات في هذا الوقت المناسب له.",
            "hours_opens_in": "يفتح بعد {t}", "hours_u_h": "س", "hours_u_m": "د",
            "remind_fail": "تعذّر فتح التقويم. حاول مرة أخرى"
        ]
    ]
}
