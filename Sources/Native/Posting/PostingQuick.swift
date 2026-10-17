import SwiftUI

/**
 БЫСТРАЯ ИЛИ ПОДРОБНАЯ ПОДАЧА (владелец: «сделай всё, что предлагаешь»; пачка 83 — без отдельного экрана выбора).

 Новое объявление открывается сразу камерой: короткий путь главный (фото → Kliko AI заполняет название, раздел и
 характеристики тем же recognize → «Проверьте»: подсказка цены по рынку, город из настроек профиля, «Опубликовать»;
 всё правится на том же экране). «Подробно — выбрать раздел и заполнить по шагам» — ссылка на экране камеры: «Что
 размещаете?» и все шаги. Последний выбор запоминается: выбрали «Подробно» — следующая подача начнётся с «Что
 размещаете?», а на нём ссылка «Быстро — с камеры». С «Проверьте» — «Подробнее — по шагам»: обычный мастер с уже
 заполненными полями. Новых запросов к сайту нет — та же подача.

 Прежний экран «Быстро / Подробно» (ЭкранВыбораПодачи с советами) убран: лишний экран и лишнее касание в каждой подаче.
 */
enum ПамятьРежимаПодачи {
    private static let ключ = "kliko.posting.mode"

    /// "quick" или "full"; nil — ещё не выбирали.
    static var последний: String? {
        get { UserDefaults.standard.string(forKey: ключ) }
        set { UserDefaults.standard.set(newValue, forKey: ключ) }
    }
}

extension ПодачаМодель {

    /**
     Первый экран новой подачи (чистаяФорма): камера, а если в прошлый раз выбрали «Подробно» — «Что размещаете?».
     Прежняя запись ИИ-фото новой подачи — прочь, пока форма чистая (раньше это делал экран выбора; один раз на открытую
     подачу — «Подать ещё» её не трогает). Черновик («Продолжить») сюда не приходит: его запись ИИ-фото цела.
     */
    func открытьПервыйЭкран() {
        ИИФотоПодачи.shared.начатьЗаново(self)
        /* «Подойдёт N людям» и выбор «Сообщить им» прежней подачи — прочь (PostingFitDemand.swift; без сети). */
        СпросПодачи.shared.новаяПодача(self)
        if ПамятьРежимаПодачи.последний == "full" {
            безФото()
        } else {
            экран = .камера
        }
    }

    /// «Быстро — с камеры» на «Что размещаете?»: экран фото короткого пути; следующая подача — тоже с камеры.
    func выбратьБыструюПодачу() {
        ПамятьРежимаПодачи.последний = "quick"
        быстрый = false
        кКамере()
    }

    /// «Подробно — выбрать раздел и заполнить по шагам» на камере: «Что размещаете?» и полный путь по шагам.
    func выбратьПодробнуюПодачу() {
        ПамятьРежимаПодачи.последний = "full"
        /* «Продать своё» (владелец 17.10.2026): раздел уже из «Моего» — сразу шаги с ним; плитки «Что размещаете?»
           сменили бы раздел и тип подачи, заполненное из «Моего» осталось бы не на своих местах. */
        if заготовка != nil && !правка && !форма.раздел.isEmpty {
            быстрый = false
            шаг = .фото
            мастер = nil
            экран = .шаги
            запланироватьЧерновик()
            return
        }
        безФото()
    }

    /**
     «Подробнее — по шагам» с «Проверьте»: тот же черновик в обычном мастере. Раздел есть — сразу «Данные»
     (фото уже сняты), раздела нет — «Что размещаете?» (снимки и поля остаются).
     */
    func подробнееПоШагам() {
        guard !правка else { return }
        ошибкиПолей = [:]
        мастер = nil
        guard !форма.раздел.isEmpty else {
            безФото()
            return
        }
        быстрый = false
        шаг = .данные
        экран = .шаги
        запланироватьЧерновик()
    }
}

/// «Подробнее — по шагам» под «Проверьте»: тот же черновик в обычном мастере.
struct КнопкаПодробнееПодачи: View {
    let действие: () -> Void

    init(действие: @escaping () -> Void) {
        self.действие = действие
    }

    var body: some View {
        Button(action: действие) {
            HStack(spacing: 8) {
                Image(systemName: "list.number")
                    .accessibilityHidden(true)
                Text(БыстраяПодачаText.т("qm_more"))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .accessibilityHidden(true)
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(КраскаПодачи.хорошоТекст)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(КраскаПодачи.хорошоФон, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
    }
}

/// Мелкая ссылка пути подачи: «Подробно — выбрать раздел…» на камере, «Быстро — с камеры» на «Что размещаете?».
struct СсылкаПутиПодачи: View {
    let подпись: String
    let значок: String
    let действие: () -> Void

    init(_ подпись: String, значок: String, действие: @escaping () -> Void) {
        self.подпись = подпись
        self.значок = значок
        self.действие = действие
    }

    var body: some View {
        Button(action: действие) {
            Label(подпись, systemImage: значок)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(КраскаПодачи.хорошоТекст)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Тексты (ru / kk / en / ar)

enum БыстраяПодачаText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь: [String: String]
        switch язык {
        case "kk": словарь = kk
        case "en": словарь = en
        case "ar": словарь = ar
        default: словарь = ru
        }
        return словарь[ключ] ?? ru[ключ] ?? ключ
    }

    private static let ru: [String: String] = [
        "qm_more": "Подробнее — по шагам"
    ]

    private static let kk: [String: String] = [
        "qm_more": "Толығырақ — қадаммен"
    ]

    private static let en: [String: String] = [
        "qm_more": "More details — step by step"
    ]

    private static let ar: [String: String] = [
        "qm_more": "تفاصيل أكثر — خطوة بخطوة"
    ]
}
