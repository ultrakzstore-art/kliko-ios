import SwiftUI
import UIKit

/**
 ПОДАЧА — ОБЩИЕ ДЕТАЛИ ЭКРАНА, ЭТАП 42 (владелец 26.09.2026: «всё одно и то же, просто код разный»).

 Краска и формы — из CSS кабинета сайта (css/cabinet.css, css/cabinet-parts.min.css): белая карточка .card со
 скруглением --r-md и кромкой --line, поле .inp с кромкой 1.5 px, чипы .chip (выбранный — мятный с зелёной кромкой),
 переключатель .sw-row, плитки стартового окна .rw2-tile, зелёная кнопка .btn-g с градиентом. Цвета — Theme: светлая и
 тёмная тема сами.
 */

/// Карточка шага (.card): заголовок и содержимое.
struct КарточкаПодачи<Содержимое: View>: View {
    let заголовок: String?
    let подпись: String?
    let содержимое: Содержимое

    init(_ заголовок: String? = nil, подпись: String? = nil, @ViewBuilder содержимое: () -> Содержимое) {
        self.заголовок = заголовок
        self.подпись = подпись
        self.содержимое = содержимое()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let заголовок {
                VStack(alignment: .leading, spacing: 3) {
                    Text(заголовок)
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(Theme.текст)
                        .accessibilityAddTraits(.isHeader)
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
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
    }
}

/// Подпись поля (.field label): «Описание * обязательно», «Ваша цена · необязательно».
struct ПодписьПоля: View {
    let текст: String
    let обязательно: Bool
    let необязательно: Bool

    init(_ текст: String, обязательно: Bool = false, необязательно: Bool = false) {
        self.текст = текст
        self.обязательно = обязательно
        self.необязательно = необязательно
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(текст)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.текст)
            if обязательно {
                Text("* " + ПодачаText.т("form_required"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.ценаСкидка)
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
        .padding(.horizontal, 12)
        .frame(minHeight: 46)
        .background(заблокировано ? Theme.поверхность2 : Theme.поверхность,
                    in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                .strokeBorder(ошибка ? Theme.ценаСкидка : Theme.линия, lineWidth: ошибка ? 2 : 1.5)
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

/// Многострочное поле (textarea описания) с подсказкой внутри; ошибка — красная кромка.
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
                    .foregroundStyle(Theme.текстВторой.opacity(0.8))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .accessibilityHidden(true)
            }
            TextEditor(text: ограниченный)
                .font(.system(size: 16))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .frame(minHeight: 130)
                .accessibilityLabel(подсказка)
                .modifier(ФокусПоля(фокус: фокус, ключ: ключ))
        }
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                .strokeBorder(ошибка ? Theme.ценаСкидка : Theme.линия, lineWidth: ошибка ? 2 : 1.5)
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

/// Чип .chip / .rw2-chip: выбранный — мятный с зелёной кромкой.
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
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(выбран ? Theme.акцент : Theme.текст)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minHeight: 38)
                .background(выбран ? Theme.оттенокАкцента : Theme.поверхность, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(выбран ? Theme.акцент : Theme.линия, lineWidth: 1.5)
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(выбран ? .isSelected : [])
    }
}

/// Строка-переключатель .sw-row: заголовок, подпись, системный Toggle в краске сайта.
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
                    .foregroundStyle(Theme.текст)
                if let подпись, !подпись.isEmpty {
                    Text(подпись)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(Theme.зелёныйЯркий)
        .disabled(заблокировано)
    }
}

/// Строка-кнопка выбора (select сайта): подпись и значение, стрелка; открывает список.
struct СтрокаВыбора: View {
    let значение: String
    let подсказка: String
    let действие: () -> Void

    init(_ значение: String, подсказка: String, действие: @escaping () -> Void) {
        self.значение = значение
        self.подсказка = подсказка
        self.действие = действие
    }

    var body: some View {
        Button(action: действие) {
            HStack(spacing: 8) {
                Text(значение.isEmpty ? подсказка : значение)
                    .font(.system(size: 16))
                    .foregroundStyle(значение.isEmpty ? Theme.текстВторой : Theme.текст)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 46)
            .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                    .strokeBorder(Theme.линия, lineWidth: 1.5)
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

    var body: some View {
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

/// Главная зелёная кнопка (.btn-g): градиент, белый жирный текст; занята — колёсико.
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
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(LinearGradient(colors: [Theme.зелёный, Theme.зелёный2], startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
        .disabled(занято)
    }
}

/// Вторичная кнопка (.btn-o): светлая с кромкой.
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
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.текст)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                        .strokeBorder(Theme.линия, lineWidth: 1)
                }
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
    }
}

/// Цветная заметка (.pc-esc-note, плашки tint-ok / tint-warn / tint-info сайта).
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
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(передний)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(фон, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
    }

    private var передний: Color {
        switch тон {
        case .хорошо: return КраскаОбъявлений.хорошоТекст
        case .внимание: return КраскаОбъявлений.предупреждениеТекст
        case .инфо: return КраскаОбъявлений.инфоТекст
        case .плохо: return КраскаОбъявлений.плохоТекст
        case .серый: return Theme.текстВторой
        }
    }

    private var фон: Color {
        switch тон {
        case .хорошо: return КраскаОбъявлений.хорошоФон
        case .внимание: return КраскаОбъявлений.предупреждениеФон
        case .инфо: return КраскаОбъявлений.инфоФон
        case .плохо: return КраскаОбъявлений.плохоФон
        case .серый: return Theme.поверхность2
        }
    }
}
