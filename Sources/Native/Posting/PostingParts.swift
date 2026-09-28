import SwiftUI
import UIKit

/**
 ПОДАЧА — ОБЩИЕ ДЕТАЛИ ЭКРАНА, ЭТАП 42 (владелец 26.09.2026: «всё одно и то же, просто код разный»).

 Краска и формы — из CSS кабинета сайта (css/cabinet.css, css/cabinet-parts.min.css): фон страницы --bg, карточка .ecard
 (--card, скругление 14, кромка --line 1 px, лёгкая тень), поле .inp (--surf2, кромка 1 px, скругление 12), select —
 на --card со стрелкой вниз, чипы .chip (выбранный — --g с белым), строка-переключатель .sw-row, кнопки .ast-next,
 .ast-back и .btn-g. Цвета — КраскаПодачи: токены кабинета, светлая и тёмная тема (в тёмной карточка светлее фона,
 поле — ещё светлее).
 */

/// Токены кабинета (css/cabinet.css :root и [data-theme=dark]) — у кабинета своя краска, не витрины.
enum КраскаПодачи {
    /// --bg
    static let фон = Theme.цвет(0xEEF3F0, 0x101017)
    /// Зелёное сияние сверху страницы (radial-gradient body).
    static let сияние = Theme.цвет(светлый: Theme.hex(0x1D7D4A, 0.10), тёмный: Theme.hex(0x34C997, 0.10))
    /// --card
    static let карточка = Theme.цвет(0xFFFFFF, 0x1C1C26)
    /// --surf2 (заливка .inp)
    static let поле = Theme.цвет(0xF6FAF8, 0x23232F)
    /// --line
    static let линия = Theme.цвет(светлый: Theme.hex(0xE6EFE9), тёмный: Theme.hex(0xFFFFFF, 0.10))
    /// --ink
    static let текст = Theme.цвет(0x0F1712, 0xEAF3EE)
    /// --acc-on
    static let акцентТекст = Theme.цвет(0x0F5132, 0x5CD39A)
    /// Тень .ecard — только в светлой теме.
    static let тень = Theme.цвет(светлый: Theme.hex(0x0D1B14, 0.05), тёмный: Theme.hex(0x000000, 0))
    /// --tint-ok / --on-ok
    static let хорошоФон = Theme.цвет(светлый: Theme.hex(0xE7F6EE), тёмный: Theme.hex(0x34C997, 0.14))
    static let хорошоТекст = Theme.цвет(0x0F7A44, 0x5CD39A)
    /// --tint-warn / --on-warn, кромка #add-ver-bar
    static let вниманиеФон = Theme.цвет(светлый: Theme.hex(0xFFF4E5), тёмный: Theme.hex(0xE0BD5E, 0.15))
    static let вниманиеТекст = Theme.цвет(0x92400E, 0xE0BD5E)
    static let вниманиеКромка = Theme.цвет(светлый: Theme.hex(0xFDE68A), тёмный: Theme.hex(0xE0BD5E, 0.34))
    /// --tint-bad / --on-bad
    static let плохоФон = Theme.цвет(светлый: Theme.hex(0xFEE2E2), тёмный: Theme.hex(0xFF6168, 0.15))
    static let плохоТекст = Theme.цвет(0x991B1B, 0xFF8A8F)
    /// --tint-info / --on-info / --edge-info
    static let инфоФон = Theme.цвет(светлый: Theme.hex(0xEEF4FF), тёмный: Theme.hex(0x60A5FA, 0.15))
    static let инфоТекст = Theme.цвет(0x1E40AF, 0x7CB8F5)
    static let инфоКромка = Theme.цвет(светлый: Theme.hex(0xC7D6F5), тёмный: Theme.hex(0x60A5FA, 0.34))
}

/// Фон страницы кабинета: --bg и зелёное сияние сверху.
struct ФонПодачи: View {
    var body: some View {
        КраскаПодачи.фон
            .overlay(alignment: .top) {
                RadialGradient(colors: [КраскаПодачи.сияние, КраскаПодачи.сияние.opacity(0)],
                               center: UnitPoint(x: 0.5, y: 0), startRadius: 0, endRadius: 420)
                    .frame(height: 380)
                    .allowsHitTesting(false)
            }
            .ignoresSafeArea()
    }
}

/// Карточка шага (.ecard): заголовок .section-title со значком в мятном квадрате и содержимое.
struct КарточкаПодачи<Содержимое: View>: View {
    let заголовок: String?
    let подпись: String?
    let значок: String?
    let содержимое: Содержимое

    init(_ заголовок: String? = nil, подпись: String? = nil, значок: String? = nil,
         @ViewBuilder содержимое: () -> Содержимое) {
        self.заголовок = заголовок
        self.подпись = подпись
        self.значок = значок
        self.содержимое = содержимое()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let заголовок {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        if let значок {
                            Image(systemName: значок)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Theme.акцент)
                                .frame(width: 33, height: 33)
                                .background(Theme.оттенокАкцента,
                                            in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                                .accessibilityHidden(true)
                        }
                        Text(заголовок)
                            .font(.system(size: 14, weight: .heavy))
                            .kerning(-0.2)
                            .foregroundStyle(КраскаПодачи.текст)
                            .accessibilityAddTraits(.isHeader)
                    }
                    if let подпись {
                        Text(подпись)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.текстВторой)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            содержимое
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(КраскаПодачи.карточка, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(КраскаПодачи.линия, lineWidth: 1)
        }
        .shadow(color: КраскаПодачи.тень, radius: 6, y: 2)
    }
}

/// Подпись поля: .field-lbl (15/700, чернила) или мелкая .field-sub (13/600, серая); «* обязательно», «· необязательно».
struct ПодписьПоля: View {
    let текст: String
    let обязательно: Bool
    let необязательно: Bool
    let мелкая: Bool

    init(_ текст: String, обязательно: Bool = false, необязательно: Bool = false, мелкая: Bool = false) {
        self.текст = текст
        self.обязательно = обязательно
        self.необязательно = необязательно
        self.мелкая = мелкая
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(текст)
                .font(.system(size: мелкая ? 13 : 15, weight: мелкая ? Font.Weight.semibold : Font.Weight.bold))
                .foregroundStyle(мелкая ? Theme.текстВторой : КраскаПодачи.текст)
            if обязательно {
                HStack(spacing: 3) {
                    Text("*")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(КраскаПодачи.плохоТекст)
                    Text(ПодачаText.т("form_required"))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.текстВторой)
                }
            }
            if необязательно {
                Text("· " + ПодачаText.т("form_optional"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Поле ввода .inp: ошибка — красная кромка, единица («км», «м²») — серым справа, фокус — от панели над клавиатурой.
/// предел > 0 — не длиннее стольких знаков (и при вставке); счётчик «N/предел» под полем — всегда (счётчик: true)
/// или с ПределыПодачи.счётчикЗаранее знаков до предела; на пределе он красный.
struct ПолеПодачи: View {
    let подсказка: String
    @Binding var текст: String
    let клавиатура: UIKeyboardType
    let заглавные: TextInputAutocapitalization
    let заблокировано: Bool
    let фокус: FocusState<String?>.Binding?
    let ключ: String?
    let ошибка: Bool
    let единица: String
    let предел: Int
    let счётчик: Bool

    init(_ подсказка: String, текст: Binding<String>, клавиатура: UIKeyboardType = .default,
         заглавные: TextInputAutocapitalization = .sentences, заблокировано: Bool = false,
         фокус: FocusState<String?>.Binding? = nil, ключ: String? = nil, ошибка: Bool = false, единица: String = "",
         предел: Int = 0, счётчик: Bool = false) {
        self.подсказка = подсказка
        self._текст = текст
        self.клавиатура = клавиатура
        self.заглавные = заглавные
        self.заблокировано = заблокировано
        self.фокус = фокус
        self.ключ = ключ
        self.ошибка = ошибка
        self.единица = единица
        self.предел = предел
        self.счётчик = счётчик
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            поле
            if видноСчётчик {
                СчётчикЗнаковПодачи(длина: текст.count, предел: предел)
            }
        }
    }

    private var видноСчётчик: Bool {
        guard предел > 0, !заблокировано else { return false }
        return счётчик || текст.count >= предел - ПределыПодачи.счётчикЗаранее
    }

    /// maxlength: лишнее (набор или вставка) отрезается сразу.
    private var ограниченный: Binding<String> {
        let предел = self.предел
        let связь = $текст
        guard предел > 0 else { return связь }
        return Binding(get: { связь.wrappedValue }, set: { новое in
            связь.wrappedValue = ПределыПодачи.обрезать(новое, предел)
        })
    }

    private var поле: some View {
        HStack(spacing: 6) {
            TextField(подсказка, text: ограниченный)
                .font(.system(size: 16))
                .foregroundStyle(заблокировано ? Theme.текстВторой : КраскаПодачи.текст)
                .keyboardType(клавиатура)
                .textInputAutocapitalization(заглавные)
                .disabled(заблокировано)
                .modifier(ФокусПоля(фокус: фокус, ключ: ключ))
            if !единица.isEmpty {
                Text(единица)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 46)
        .background(КраскаПодачи.поле, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                .strokeBorder(ошибка ? Theme.ценаСкидка : КраскаПодачи.линия, lineWidth: ошибка ? 2 : 1)
        }
    }
}

/// Счётчик «N/предел» под коротким полем; на пределе — красный.
struct СчётчикЗнаковПодачи: View {
    let длина: Int
    let предел: Int

    var body: some View {
        Text(String(длина) + "/" + String(предел))
            .font(.system(size: 12, weight: длина >= предел ? .semibold : .regular).monospacedDigit())
            .foregroundStyle(длина >= предел ? Theme.ценаСкидка : Theme.текстВторой)
            .accessibilityHidden(true)
    }
}

/// Многострочное поле (textarea описания, rows=6: высота 174, отступ 14, строка 24) с подсказкой внутри.
struct ТекстПодачи: View {
    let подсказка: String
    @Binding var текст: String
    let предел: Int
    let фокус: FocusState<String?>.Binding?
    let ключ: String?
    let ошибка: Bool

    init(_ подсказка: String, текст: Binding<String>, предел: Int = 5000,
         фокус: FocusState<String?>.Binding? = nil, ключ: String? = nil, ошибка: Bool = false) {
        self.подсказка = подсказка
        self._текст = текст
        self.предел = предел
        self.фокус = фокус
        self.ключ = ключ
        self.ошибка = ошибка
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if текст.isEmpty {
                Text(подсказка)
                    .font(.system(size: 16))
                    .lineSpacing(5)
                    .foregroundStyle(Theme.текстВторой.opacity(0.8))
                    .padding(14)
                    .accessibilityHidden(true)
            }
            TextEditor(text: ограниченный)
                .font(.system(size: 16))
                .lineSpacing(5)
                .foregroundStyle(КраскаПодачи.текст)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .frame(minHeight: 174)
                .accessibilityLabel(подсказка)
                .modifier(ФокусПоля(фокус: фокус, ключ: ключ))
        }
        .background(КраскаПодачи.поле, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                .strokeBorder(ошибка ? Theme.ценаСкидка : КраскаПодачи.линия, lineWidth: ошибка ? 2 : 1)
        }
    }

    /// maxlength сайта.
    private var ограниченный: Binding<String> {
        let предел = self.предел
        let связь = $текст
        return Binding(get: { связь.wrappedValue }, set: { новое in
            связь.wrappedValue = новое.count > предел ? String(новое.prefix(предел)) : новое
        })
    }
}

/// Чип .chip: 13/600 серым, кромка --line, скругление 14; выбранный — --g с белым текстом.
struct ЧипПодачи: View {
    let текст: String
    let выбран: Bool
    let действие: () -> Void

    init(_ текст: String, выбран: Bool, действие: @escaping () -> Void) {
        self.текст = текст
        self.выбран = выбран
        self.действие = действие
    }

    var body: some View {
        Button(action: действие) {
            Text(текст)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(выбран ? Color.white : Theme.текстВторой)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(выбран ? Theme.зелёный : КраскаПодачи.карточка,
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                        .strokeBorder(выбран ? Theme.зелёный : КраскаПодачи.линия, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(выбран ? .isSelected : [])
    }
}

/// Пресет часов .hours-preset: высота 38, кромка --line, скругление 12, 13/700 и значок 15 (shuffle / clock);
/// выбранный — --acc-on с белым.
struct ЧипЧасовПодачи: View {
    let текст: String
    let значок: String
    let выбран: Bool
    let действие: () -> Void

    init(_ текст: String, значок: String, выбран: Bool, действие: @escaping () -> Void) {
        self.текст = текст
        self.значок = значок
        self.выбран = выбран
        self.действие = действие
    }

    var body: some View {
        Button(action: действие) {
            HStack(spacing: 6) {
                Image(systemName: значок)
                    .font(.system(size: 13, weight: .semibold))
                    .opacity(0.85)
                    .accessibilityHidden(true)
                Text(текст)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
            }
            .foregroundStyle(выбран ? Color.white : КраскаПодачи.текст)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(выбран ? КраскаПодачи.акцентТекст : КраскаПодачи.карточка,
                        in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                    .strokeBorder(выбран ? КраскаПодачи.акцентТекст : КраскаПодачи.линия, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(выбран ? .isSelected : [])
    }
}

/// «Посуточно / Помесячно» (.rent-seg): на --card с кромкой 1.5 и отступом 4; выбранная — градиент --g → --g2.
struct СегментАрендыПодачи: View {
    let варианты: [ВариантПоля]
    @Binding var значение: String

    init(_ варианты: [ВариантПоля], значение: Binding<String>) {
        self.варианты = варианты
        self._значение = значение
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(варианты, id: \.self) { в in
                кнопка(в)
            }
        }
        .padding(4)
        .background(КраскаПодачи.карточка, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                .strokeBorder(КраскаПодачи.линия, lineWidth: 1.5)
        }
    }

    private func кнопка(_ в: ВариантПоля) -> some View {
        let выбран = значение == в.ключ
        return Button {
            значение = в.ключ
            ОткликСайта.выбор()
        } label: {
            Text(в.подпись)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(выбран ? Color.white : Theme.текстВторой)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background {
                    if выбран {
                        RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous)
                            .fill(LinearGradient(colors: [Theme.зелёный, Theme.зелёный2],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(выбран ? .isSelected : [])
    }
}

/// Строка-переключатель .sw-row: рамка на --card, включённая — на --tint-ok с кромкой --acc-on.
struct ПереключательПодачи: View {
    let заголовок: String
    let подпись: String?
    @Binding var включено: Bool
    let заблокировано: Bool

    init(_ заголовок: String, подпись: String? = nil, включено: Binding<Bool>, заблокировано: Bool = false) {
        self.заголовок = заголовок
        self.подпись = подпись
        self._включено = включено
        self.заблокировано = заблокировано
    }

    var body: some View {
        Toggle(isOn: $включено) {
            VStack(alignment: .leading, spacing: 2) {
                Text(заголовок)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(КраскаПодачи.текст)
                    .fixedSize(horizontal: false, vertical: true)
                if let подпись, !подпись.isEmpty {
                    Text(подпись)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(Theme.зелёный2)
        .disabled(заблокировано)
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 50)
        .background(включено ? КраскаПодачи.хорошоФон : КраскаПодачи.карточка,
                    in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(включено ? КраскаПодачи.акцентТекст : КраскаПодачи.линия, lineWidth: 1)
        }
    }
}

/// Строка-кнопка выбора (select.inp сайта): значение и стрелка вниз; открывает список. Раздел и характеристики — на
/// --card, бренд — на --surf2.
struct СтрокаВыбора: View {
    let значение: String
    let подсказка: String
    let заливка: Color
    let действие: () -> Void

    init(_ значение: String, подсказка: String, заливка: Color = КраскаПодачи.карточка, действие: @escaping () -> Void) {
        self.значение = значение
        self.подсказка = подсказка
        self.заливка = заливка
        self.действие = действие
    }

    var body: some View {
        Button(action: действие) {
            HStack(spacing: 8) {
                Text(значение.isEmpty ? подсказка : значение)
                    .font(.system(size: 16))
                    .foregroundStyle(значение.isEmpty ? Theme.текстВторой : КраскаПодачи.текст)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 46)
            .background(заливка, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                    .strokeBorder(КраскаПодачи.линия, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(подсказка)
        .accessibilityValue(значение)
    }
}

/// Список для выбора (select с «Другое — вписать»): поиск, варианты, своя строка.
struct СписокВыбора: Identifiable {
    let id = UUID()
    let заголовок: String
    let варианты: [ВариантПоля]
    /// Подпись строки «своё значение»; nil — только из списка.
    let своё: String?
    /// Подпись «не указано» (сбросить); nil — без неё.
    let сброс: String?
    /// Открыть сразу строкой «впишите вручную» (пункт «Другое (вписать)…» из меню).
    let пишу: Bool
    /// Предел своего значения (ПределыПодачи.короткое); 0 — без предела.
    let предел: Int
    let выбрано: (String) -> Void

    init(заголовок: String, варианты: [ВариантПоля], своё: String? = nil, сброс: String? = nil, пишу: Bool = false,
         предел: Int = ПределыПодачи.короткое, выбрано: @escaping (String) -> Void) {
        self.заголовок = заголовок
        self.варианты = варианты
        self.своё = своё
        self.сброс = сброс
        self.пишу = пишу
        self.предел = предел
        self.выбрано = выбрано
    }
}

struct ЛистВыбора: View {
    let список: СписокВыбора
    @Environment(\.dismiss) private var закрыть
    @State private var поиск = ""
    @State private var своёЗначение = ""
    @State private var пишу = false

    init(список: СписокВыбора) {
        self.список = список
        _пишу = State(initialValue: список.пишу)
    }

    /// Короткий список — лист по высоте строк, без пустоты снизу; длинный (с поиском) — большой, чтобы не прыгал.
    @ViewBuilder
    var body: some View {
        if список.варианты.count <= 12 {
            стопка
                .листПоВысоте()
        } else {
            /* Длинный: большой лист; метки строк никуда не отдают высоту (и не двигают лист под этим). */
            стопка
                .environment(\.отдатьВысотуЛиста, nil)
        }
    }

    private var стопка: some View {
        NavigationStack {
            List {
                if пишу {
                    Section {
                        TextField(ПодачаText.т("spec_write_manually"), text: своёОграниченное)
                        if список.предел > 0 && своёЗначение.count >= список.предел - ПределыПодачи.счётчикЗаранее {
                            СчётчикЗнаковПодачи(длина: своёЗначение.count, предел: список.предел)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        Button(ПодачаText.т("done")) {
                            let чистое = ПределыПодачи.обрезать(своёЗначение.trimmingCharacters(in: .whitespacesAndNewlines),
                                                                 список.предел)
                            guard !чистое.isEmpty else { return }
                            список.выбрано(чистое)
                            закрыть()
                        }
                        .disabled(своёЗначение.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                if let сброс = список.сброс {
                    Button(сброс) {
                        список.выбрано("")
                        закрыть()
                    }
                    .foregroundStyle(Theme.текстВторой)
                }
                ForEach(видимые, id: \.self) { вариант in
                    Button {
                        список.выбрано(вариант.ключ)
                        закрыть()
                    } label: {
                        Text(вариант.подпись)
                            .foregroundStyle(Theme.текст)
                    }
                    .мерилоФормы()
                }
                if let своё = список.своё, !пишу {
                    Button(своё) { пишу = true }
                        .foregroundStyle(Theme.акцент)
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $поиск)
            .navigationTitle(список.заголовок)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ПодачаText.т("close")) { закрыть() }
                }
            }
        }
        .tint(Theme.акцент)
    }

    /// Своё значение не длиннее предела списка — и при вставке.
    private var своёОграниченное: Binding<String> {
        let предел = список.предел
        let связь = $своёЗначение
        guard предел > 0 else { return связь }
        return Binding(get: { связь.wrappedValue }, set: { новое in
            связь.wrappedValue = ПределыПодачи.обрезать(новое, предел)
        })
    }

    private var видимые: [ВариантПоля] {
        let q = поиск.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return список.варианты }
        return список.варианты.filter { $0.подпись.lowercased().contains(q) }
    }
}

/// Кнопка отправки (#submit-btn.btn-g): градиент --g → --g2 по диагонали, 15/700, высота 46; занята — колёсико.
struct КнопкаПодачи: View {
    let текст: String
    let занято: Bool
    let действие: () -> Void

    init(_ текст: String, занято: Bool = false, действие: @escaping () -> Void) {
        self.текст = текст
        self.занято = занято
        self.действие = действие
    }

    var body: some View {
        Button(action: действие) {
            HStack(spacing: 8) {
                if занято {
                    SiteSpinner.белый
                }
                Text(текст)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(LinearGradient(colors: [Theme.зелёный, Theme.зелёный2], startPoint: .topLeading,
                                       endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .shadow(color: Color(uiColor: Theme.hex(0x0F5132, 0.45)), radius: 6, y: 6)
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
        .disabled(занято)
    }
}

/// «Далее →» (.ast-next): заливка --acc-on, белый 16/800, высота 46, скругление 14, мягкая тень.
struct КнопкаДалееПодачи: View {
    let текст: String
    let действие: () -> Void

    init(_ текст: String, действие: @escaping () -> Void) {
        self.текст = текст
        self.действие = действие
    }

    var body: some View {
        Button(action: действие) {
            Text(текст)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(КраскаПодачи.акцентТекст, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                .shadow(color: Color(uiColor: Theme.hex(0x0F5132, 0.28)), radius: 8, y: 10)
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
    }
}

/// Вторичная кнопка (как .ast-back): --surf2 с кромкой, 16/800, высота 46.
struct КнопкаПодачиВторая: View {
    let текст: String
    let действие: () -> Void

    init(_ текст: String, действие: @escaping () -> Void) {
        self.текст = текст
        self.действие = действие
    }

    var body: some View {
        Button(action: действие) {
            Text(текст)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(КраскаПодачи.текст)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(КраскаПодачи.поле, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                        .strokeBorder(КраскаПодачи.линия, lineWidth: 1)
                }
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
    }
}

/// Цветная заметка (плашки --tint-ok / --tint-warn / --tint-info / --tint-bad кабинета; серая — --surf2 с кромкой).
struct ЗаметкаПодачи: View {
    enum Тон { case хорошо, внимание, инфо, плохо, серый }

    let текст: String
    let тон: Тон
    let значок: String?

    init(_ текст: String, тон: Тон = .инфо, значок: String? = nil) {
        self.текст = текст
        self.тон = тон
        self.значок = значок
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let значок {
                Image(systemName: значок)
                    .font(.system(size: 14, weight: .semibold))
                    .accessibilityHidden(true)
            }
            Text(текст)
                .font(.system(size: тон == .серый ? 12 : 13))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(передний)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(фон, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        .overlay {
            if тон == .серый {
                RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                    .strokeBorder(КраскаПодачи.линия, lineWidth: 1)
            }
        }
    }

    private var передний: Color {
        switch тон {
        case .хорошо: return КраскаПодачи.хорошоТекст
        case .внимание: return КраскаПодачи.вниманиеТекст
        case .инфо: return КраскаПодачи.инфоТекст
        case .плохо: return КраскаПодачи.плохоТекст
        case .серый: return Theme.текстВторой
        }
    }

    private var фон: Color {
        switch тон {
        case .хорошо: return КраскаПодачи.хорошоФон
        case .внимание: return КраскаПодачи.вниманиеФон
        case .инфо: return КраскаПодачи.инфоФон
        case .плохо: return КраскаПодачи.плохоФон
        case .серый: return КраскаПодачи.поле
        }
    }
}
