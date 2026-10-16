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
 «Моё» и «Гараж, устройства, рост и мерки»; справа — три мини-кольца профилей и стрелка строки. Пусто — чип «Заполните
 за пару минут», всё заполнено — печать.
 */
struct КарточкаМоегоКабинета: View {
    let перейти: () -> Void
    @ObservedObject private var хранилище = МоёХранилище.shared
    @State private var прыжки = 0

    init(перейти: @escaping () -> Void) {
        self.перейти = перейти
    }

    var body: some View {
        let запись = хранилище.запись
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
                правая(запись)
                СтрелкаСтрокиКабинета()
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 84)
            .background(Theme.поверхность, in: форма)
            .теньКарточкиСайта(радиус: Theme.Радиус.md)
            .contentShape(форма)
            .animation(ДвижениеСайта.смена, value: запись.пусто)
            .animation(ДвижениеСайта.смена, value: запись.всёГотово)
        }
        .buttonStyle(НажатиеСайта())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(МоёText.т("my_title") + ". " + подписьДоступности(запись))
        .accessibilityAddTraits(.isButton)
        .onAppear { хранилище.подготовить() }
        .onChange(of: запись.всёГотово) { было, стало in
            // «Уменьшение движения» и лёгкий режим — без прыжка печати.
            if стало && !было && !(ДвижениеСайта.тихо || РежимУстройства.shared.лёгкий) { прыжки += 1 }
        }
    }

    @ViewBuilder
    private func правая(_ запись: ЗаписьМоего) -> some View {
        if запись.пусто {
            Text(МоёText.т("my_start"))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.акцент)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.оттенокАкцента, in: Capsule())
                .frame(maxWidth: 120)
                .transition(.opacity)
        } else if запись.всёГотово {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.акцент)
                .symbolEffect(.bounce, value: прыжки)
                .transition(.scale.combined(with: .opacity))
        } else {
            HStack(spacing: 5) {
                ForEach(ПрофильМоего.allCases) { профиль in
                    КольцоМоего(доля: профиль.прогресс(запись).доля, размер: 22, толщина: 2.5, номер: профиль.rawValue,
                                цвет: профиль.цвет, процент: false)
                        .overlay {
                            Image(systemName: профиль.значок)
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(профиль.цвет)
                        }
                }
            }
            .transition(.opacity)
        }
    }

    private func подписьДоступности(_ запись: ЗаписьМоего) -> String {
        if запись.пусто { return МоёText.т("my_cab_sub") + ". " + МоёText.т("my_start") }
        if запись.всёГотово { return МоёText.т("my_all_set") }
        return String(format: МоёText.т("my_ready"), ПроцентМоего.текст(запись.готовность))
    }
}
