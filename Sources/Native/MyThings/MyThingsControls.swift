import SwiftUI
import UIKit

/**
 «МОЁ» — ЭЛЕМЕНТЫ ВВОДА И КАРТОЧКА В КАБИНЕТЕ.

   · ЧипМоего — чип выбора (выбранный — зелёная заливка);
   · ПолеЧислаМоего — число с единицей и пределами: принимается, когда поле теряет фокус, вне пределов — оранжевая
     рамка и «предупреждение» под пальцем;
   · КарточкаМоегоКабинета — вход «Моё» в кабинете: широкая карточка 84 pt с тремя мини-кольцами профилей.
 Общие части экранов (кольца, шапка, каскад, переходы) — MyThingsParts.swift.
 */

// MARK: - Чип

/// Чип выбора: выбранный — зелёная заливка и белый текст, иначе оттенок акцента и тонкая рамка.
struct ЧипМоего: View {
    let текст: String
    let выбран: Bool
    var значок: String?
    let действие: () -> Void

    init(_ текст: String, выбран: Bool, значок: String? = nil, действие: @escaping () -> Void) {
        self.текст = текст
        self.выбран = выбран
        self.значок = значок
        self.действие = действие
    }

    var body: some View {
        Button(action: действие) {
            HStack(spacing: 5) {
                if let значок {
                    Image(systemName: значок)
                        .font(.caption.weight(.bold))
                        .accessibilityHidden(true)
                }
                Text(текст)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .foregroundStyle(выбран ? Color.white : Theme.акцент)
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .background(выбран ? AnyShapeStyle(Theme.зелёный2) : AnyShapeStyle(Theme.оттенокАкцента), in: Capsule())
            .overlay { Capsule().strokeBorder(Theme.рамкаПункта, lineWidth: выбран ? 0 : 1) }
            .contentShape(Capsule())
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.95))
        .accessibilityAddTraits(выбран ? .isSelected : [])
        .animation(ДвижениеСайта.выбор, value: выбран)
    }
}

// MARK: - Поле числа

/// Поле числа с единицей: «176 см», «70,6». Набранное принимается, когда поле теряет фокус: пусто — стереть, вне
/// пределов или не число — оранжевая рамка и «предупреждение» под пальцем, прежнее значение остаётся.
struct ПолеЧислаМоего: View {
    let заголовок: String
    let единица: String
    @Binding var значение: Double?
    let пределы: ClosedRange<Double>
    var знаков: Int
    var подсказка: String?
    /// false — заголовок рисует тот, кто кладёт поле (его же слышит VoiceOver).
    var показатьЗаголовок: Bool
    @State private var текст = ""
    @State private var плохо = false
    @FocusState private var фокус: Bool

    init(заголовок: String, единица: String, значение: Binding<Double?>, пределы: ClosedRange<Double>,
         знаков: Int = 1, подсказка: String? = nil, показатьЗаголовок: Bool = true) {
        self.заголовок = заголовок
        self.единица = единица
        _значение = значение
        self.пределы = пределы
        self.знаков = знаков
        self.подсказка = подсказка
        self.показатьЗаголовок = показатьЗаголовок
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if показатьЗаголовок {
                Text(заголовок)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.текст)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
            HStack(spacing: 6) {
                TextField("—", text: $текст)
                    .keyboardType(.decimalPad)
                    .focused($фокус)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(Theme.текст)
                    .accessibilityLabel(заголовок)
                    .accessibilityValue(текст.isEmpty ? "" : текст + " " + единица)
                Text(единица)
                    .font(.subheadline)
                    .foregroundStyle(Theme.текстВторой)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                    .strokeBorder(рамка, lineWidth: фокус || плохо ? 2 : 1)
            }
            if let подсказка {
                Text(подсказка)
                    .font(.caption)
                    .foregroundStyle(плохо ? Theme.оранжевый : Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(ДвижениеСайта.выбор, value: плохо)
        .onAppear { показать(значение) }
        .onChange(of: фокус) { _, стало in
            if !стало { принять() }
        }
        .onChange(of: значение) { _, новое in
            if !фокус { показать(новое) }
        }
        .onDisappear {
            if фокус { принять() }
        }
    }

    private var рамка: Color {
        if плохо { return Theme.оранжевый }
        return фокус ? Theme.акцент : Theme.линия
    }

    private func показать(_ x: Double?) {
        текст = x.map { ЧислоМоего.ч($0, знаков: знаков) } ?? ""
        плохо = false
    }

    private func принять() {
        let чистый = текст.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !чистый.isEmpty else {
            плохо = false
            if значение != nil { значение = nil }
            return
        }
        guard let x = ЧислоМоего.разобрать(чистый), пределы.contains(x) else {
            плохо = true
            ОткликСайта.предупреждение()
            return
        }
        плохо = false
        if значение != x { значение = x }
        текст = ЧислоМоего.ч(x, знаков: знаков)
    }
}

// MARK: - Карточка в кабинете

/**
 «Моё» в кабинете — видна всем, гостю тоже: широкая карточка 84 pt, как плитки. Слева значок в мятном квадрате,
 «Моё» и «Гараж, устройства, рост и мерки»; справа — мини-кольца профилей и разделов (дом, компьютер, гардероб) и
 стрелка строки. Пусто — чип «Заполните
 за пару минут», всё заполнено — печать.
 */
struct КарточкаМоегоКабинета: View, Equatable {
    let перейти: () -> Void
    @ObservedObject private var хранилище = МоёХранилище.shared
    @State private var прыжки = 0

    init(перейти: @escaping () -> Void) {
        self.перейти = перейти
    }

    /// Скорость («кабинет легче»): снаружи только устойчивый переход стека — проход кабинета карточку не трогает
    /// (вставка через .equatable()); перерисовывает её само хранилище «Моего».
    nonisolated static func == (л: КарточкаМоегоКабинета, п: КарточкаМоегоКабинета) -> Bool {
        true
    }

    /// Одно кольцо карточки: профиль или включённый раздел, его доля, краска и значок. id — номер кольца (шаг
    /// анимации КольцоМоего): профили — 0…2, разделы — следом.
    private struct КольцоКарточки: Identifiable {
        let id: Int
        let доля: Double
        let цвет: Color
        let значок: String
    }

    /// Прогресс «Моего» одним проходом: доли профилей и включённых разделов и готовность — по одному разу, а не
    /// заново в кольцах, подписи VoiceOver и анимациях (раньше — около 30 пересчётов за проход).
    private struct Сводка {
        let пусто: Bool
        let кольца: [КольцоКарточки]
        /// Включённых разделов нет — кольца крупнее (только три профиля).
        let безРазделов: Bool
        let готовность: Double
        var всёГотово: Bool { готовность > 0.995 }

        init(_ запись: ЗаписьМоего) {
            пусто = запись.пусто
            let профилей: Int = ПрофильМоего.allCases.count
            var кольца: [КольцоКарточки] = []
            for профиль in ПрофильМоего.allCases {
                кольца.append(КольцоКарточки(id: профиль.rawValue, доля: профиль.прогресс(запись).доля,
                                             цвет: профиль.цвет, значок: профиль.значок))
            }
            let разделы: [РазделМоего] = РазделМоего.включённые
            for раздел in разделы {
                кольца.append(КольцоКарточки(id: раздел.rawValue + профилей, доля: раздел.прогресс(запись).доля,
                                             цвет: раздел.цвет, значок: раздел.значок))
            }
            self.кольца = кольца
            безРазделов = разделы.isEmpty
            /* Как ЗаписьМоего.готовность: среднее трёх профилей и включённых разделов (дом, компьютер, гардероб). */
            let сумма: Double = кольца.reduce(0) { итог, кольцо in итог + кольцо.доля }
            готовность = кольца.isEmpty ? 0 : сумма / Double(кольца.count)
        }
    }

    var body: some View {
        let _ = ЗамерКабинета.тело("my", Self.self)
        let сводка = Сводка(хранилище.запись)
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
        Button(action: перейти) {
            HStack(spacing: 12) {
                ЗначокПрофиляМоего(значок: "person.crop.rectangle.stack", цвет: КраскаСтрокКабинета.значок,
                                   фон: Theme.мята)
                VStack(alignment: .leading, spacing: 2) {
                    Text(МоёText.т("my_title"))
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(Theme.текст)
                        .lineLimit(1)
                    Text(МоёText.т("my_cab_sub"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                .layoutPriority(1)
                Spacer(minLength: 6)
                правая(сводка)
                СтрелкаСтрокиКабинета()
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 84)
            .background(Theme.поверхность, in: форма)
            .теньКарточкиСайта(радиус: Theme.Радиус.md)
            .contentShape(форма)
            .animation(ДвижениеСайта.смена, value: сводка.пусто)
            .animation(ДвижениеСайта.смена, value: сводка.всёГотово)
        }
        .buttonStyle(НажатиеСайта())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(МоёText.т("my_title") + ". " + подписьДоступности(сводка))
        .accessibilityAddTraits(.isButton)
        .onAppear { хранилище.подготовить() }
        .onChange(of: сводка.всёГотово) { было, стало in
            // «Уменьшение движения» и лёгкий режим — без прыжка печати.
            if стало && !было && !(ДвижениеСайта.тихо || РежимУстройства.shared.лёгкий) { прыжки += 1 }
        }
    }

    @ViewBuilder
    private func правая(_ сводка: Сводка) -> some View {
        if сводка.пусто {
            /* Коротко и не сжимается (снимок CI 17.10.2026: «Заполните за пару минут» в рамке 120 pt сжималось до
               «Зап о…»). Полная фраза остаётся в подписи для VoiceOver. */
            Label(МоёText.т("my_add"), systemImage: "plus")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.акцент)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Theme.оттенокАкцента, in: Capsule())
                .transition(.opacity)
        } else if сводка.всёГотово {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.акцент)
                .symbolEffect(.bounce, value: прыжки)
                .transition(.scale.combined(with: .opacity))
        } else {
            // Профили и разделы v2 (дом, компьютер, гардероб) — та же схема, что у процента; шесть колец — мельче,
            // чтобы карточка влезла на iPhone SE.
            let размер: CGFloat = сводка.безРазделов ? 22 : 18
            HStack(spacing: сводка.безРазделов ? 5 : 3) {
                ForEach(сводка.кольца) { кольцо in
                    КольцоМоего(доля: кольцо.доля, размер: размер, толщина: 2.5, номер: кольцо.id,
                                цвет: кольцо.цвет, процент: false)
                        .overlay {
                            Image(systemName: кольцо.значок)
                                .font(.system(size: размер * 0.36, weight: .bold))
                                .foregroundStyle(кольцо.цвет)
                        }
                }
            }
            .transition(.opacity)
        }
    }

    private func подписьДоступности(_ сводка: Сводка) -> String {
        if сводка.пусто { return МоёText.т("my_cab_sub") + ". " + МоёText.т("my_start") }
        if сводка.всёГотово { return МоёText.т("my_all_set") }
        return String(format: МоёText.т("my_ready"), ПроцентМоего.текст(сводка.готовность))
    }
}
