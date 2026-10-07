import SwiftUI

/**
 БЫСТРАЯ ИЛИ ПОДРОБНАЯ ПОДАЧА (владелец: «сделай всё, что предлагаешь»).

 «Продать» → выбор: «Быстро (30 секунд)» — короткий путь с камеры (фото → Kliko AI заполняет название, раздел и
 характеристики тем же recognize → «Проверьте»: подсказка цены по рынку, город из настроек профиля, «Опубликовать»;
 всё правится на том же экране) или «Подробно» — «Что размещаете?» и все шаги. Последний выбор запоминается и
 подсвечен «В прошлый раз». С «Проверьте» — «Подробнее — по шагам»: обычный мастер с уже заполненными полями.
 Новых запросов к сайту нет — та же подача.
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

    /// «Быстро (30 секунд)»: экран фото короткого пути.
    func выбратьБыструюПодачу() {
        ПамятьРежимаПодачи.последний = "quick"
        быстрый = false
        экран = .камера
    }

    /// «Подробно»: «Что размещаете?» и полный путь по шагам.
    func выбратьПодробнуюПодачу() {
        ПамятьРежимаПодачи.последний = "full"
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

// MARK: - Экран выбора

struct ВыборРежимаПодачи: View {
    @ObservedObject var модель: ПодачаМодель
    let закрыть: () -> Void

    init(модель: ПодачаМодель, закрыть: @escaping () -> Void) {
        self.модель = модель
        self.закрыть = закрыть
    }

    private func т(_ ключ: String) -> String { БыстраяПодачаText.т(ключ) }

    var body: some View {
        let прошлый = ПамятьРежимаПодачи.последний
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ГеройПодачи(правка: false, закрыть: закрыть)
                Text(т("qm_title"))
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(КраскаПодачи.текст)
                    .padding(.top, 4)
                    .accessibilityAddTraits(.isHeader)
                карточка(значок: "bolt.fill", заголовок: т("qm_quick"), подпись: т("qm_quick_s"),
                         прошлый: прошлый == "quick", главная: прошлый != "full") {
                    модель.выбратьБыструюПодачу()
                }
                карточка(значок: "list.number", заголовок: т("qm_full"), подпись: т("qm_full_s"),
                         прошлый: прошлый == "full", главная: прошлый == "full") {
                    модель.выбратьПодробнуюПодачу()
                }
                Text(т("qm_hint"))
                    .font(.footnote)
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
    }

    private func карточка(значок: String, заголовок: String, подпись: String, прошлый: Bool, главная: Bool,
                          действие: @escaping () -> Void) -> some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
        return Button(action: действие) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: значок)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(КраскаПодачи.хорошоТекст)
                    .frame(width: 48, height: 48)
                    .background(КраскаПодачи.хорошоФон, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(заголовок)
                            .font(.headline.weight(.heavy))
                            .foregroundStyle(КраскаПодачи.текст)
                        if прошлый {
                            Text(т("qm_last"))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(КраскаПодачи.хорошоТекст)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(КраскаПодачи.хорошоФон, in: Capsule())
                        }
                    }
                    Text(подпись)
                        .font(.subheadline)
                        .foregroundStyle(Theme.текстВторой)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.текстВторой)
                    .padding(.top, 4)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(КраскаПодачи.карточка, in: форма)
            .overlay {
                форма.strokeBorder(главная ? КраскаПодачи.хорошоТекст : КраскаПодачи.линия, lineWidth: главная ? 2 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
        .accessibilityHint(подпись)
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
        "qm_title": "Как подать объявление?",
        "qm_quick": "Быстро (30 секунд)",
        "qm_quick_s": "Сфотографируйте — Kliko AI заполнит название, раздел и характеристики и подскажет цену. Город — из профиля",
        "qm_full": "Подробно",
        "qm_full_s": "Выберите раздел и заполните всё по шагам: характеристики, цена, адрес, доставка",
        "qm_last": "В прошлый раз",
        "qm_hint": "Из быстрой подачи всегда можно перейти к подробной — заполненное сохранится",
        "qm_more": "Подробнее — по шагам"
    ]

    private static let kk: [String: String] = [
        "qm_title": "Хабарландыруды қалай беру керек?",
        "qm_quick": "Жылдам (30 секунд)",
        "qm_quick_s": "Суретке түсіріңіз — Kliko AI атауын, бөлімін, сипаттамаларын толтырып, бағасын ұсынады. Қала — профильден",
        "qm_full": "Толық",
        "qm_full_s": "Бөлімді таңдап, бәрін қадаммен толтырыңыз: сипаттамалар, баға, мекенжай, жеткізу",
        "qm_last": "Өткен жолы",
        "qm_hint": "Жылдам берілімнен толыққа әрқашан өтуге болады — толтырылғаны сақталады",
        "qm_more": "Толығырақ — қадаммен"
    ]

    private static let en: [String: String] = [
        "qm_title": "How do you want to post?",
        "qm_quick": "Quick (30 seconds)",
        "qm_quick_s": "Take a photo — Kliko AI fills in the title, category and specs and suggests a price. City comes from your profile",
        "qm_full": "Detailed",
        "qm_full_s": "Choose a category and fill everything step by step: specs, price, address, delivery",
        "qm_last": "Last time",
        "qm_hint": "You can always switch from quick to detailed — what you filled in stays",
        "qm_more": "More details — step by step"
    ]

    private static let ar: [String: String] = [
        "qm_title": "كيف تريد نشر الإعلان؟",
        "qm_quick": "سريع (30 ثانية)",
        "qm_quick_s": "التقط صورة — سيملأ Kliko AI العنوان والقسم والمواصفات ويقترح السعر. المدينة من ملفك الشخصي",
        "qm_full": "مفصّل",
        "qm_full_s": "اختر القسم واملأ كل شيء خطوة بخطوة: المواصفات والسعر والعنوان والتوصيل",
        "qm_last": "المرة السابقة",
        "qm_hint": "يمكنك دائمًا الانتقال من السريع إلى المفصّل — يبقى ما ملأته",
        "qm_more": "تفاصيل أكثر — خطوة بخطوة"
    ]
}
