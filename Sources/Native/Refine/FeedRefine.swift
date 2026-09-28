import SwiftUI

/**
 УТОЧНЕНИЕ ЛЕНТЫ НА ТЕЛЕФОНЕ — ЭТАП 18 ПЕРЕХОДА НА SWIFTUI (владелец 25.09.2026: «следующие этапы»).

 Кнопка «Уточнить» рядом с разделами ленты открывает лист: город (из городов уже загруженных объявлений и «Любой»),
 цена от и до, «Только новые», «Сбросить». Отбор — по FeedModel.items, только для показа: сетка показывает подходящие,
 над ней чип «Уточнено по загруженным: N из M».

 🔴 ТОЛЬКО ПО ЗАГРУЖЕННОМУ, А НЕ ПО ВСЕМУ САЙТУ. Какие фильтры принимает api/listings.php, кроме cat и q, приложению
 неизвестно (исходников сайта под рукой нет), а угаданный параметр сервер молча проигнорирует — и человек решит, что
 отобрано по всему сайту. Поэтому отбираем сами и прямо говорим об этом: в листе и на чипе. Лента при этом листается
 дальше, как раньше (FeedModel.дальше), и подгруженное тоже проходит через отбор.

 Сменили поиск или раздел — уточнение сбрасывается (FeedModel): города и цены другой выдачи — другие. На телефон
 ничего не пишется. Работает одинаково в стеке iPhone и в левой колонке iPad (этап 14): лента там одна и та же.
 */
struct УточнениеЛенты: Equatable {
    /// Город точно как в объявлении; пусто — любой.
    var город = ""
    /// Цена «от» и «до» — как набрано в поле: цифры вынимаем при сравнении, пробелы и «₸» не мешают.
    var ценаОт = ""
    var ценаДо = ""
    var толькоНовые = false

    var пустое: Bool { город.isEmpty && нижняя == nil && верхняя == nil && !толькоНовые }

    var нижняя: Double? { Self.число(ценаОт) }
    var верхняя: Double? { Self.число(ценаДо) }

    /// Подходит ли объявление. Цена — та же, что на карточке: у аренды — за сутки. Задана граница цены, а у объявления
    /// цены нет («Договорная», «по запросу») — не подходит: сказать, что оно в пределах, нельзя.
    func подходит(_ товар: Listing) -> Bool {
        if !город.isEmpty && товар.city.caseInsensitiveCompare(город) != .orderedSame { return false }
        if толькоНовые && !товар.isNew { return false }
        let от = нижняя
        let до = верхняя
        if от != nil || до != nil {
            guard let цена = Self.цена(товар) else { return false }
            if let от, цена < от { return false }
            if let до, цена > до { return false }
        }
        return true
    }

    /// Цена карточки (ListingCard.цена) числом: аренда — за сутки, иначе цена продажи; нет или ноль — nil.
    static func цена(_ товар: Listing) -> Double? {
        if товар.forRent, let день = товар.rentPriceDay, день > 0 { return день }
        guard let p = товар.price, p > 0 else { return nil }
        return p
    }

    /// Только цифры из набранного: «450 000» → 450000. Пусто — границы нет.
    static func число(_ текст: String) -> Double? {
        let цифры = текст.filter { $0.isASCII && $0.isNumber }
        guard !цифры.isEmpty else { return nil }
        return Double(String(цифры.prefix(15)))
    }

    /// Города загруженных объявлений без повторов (с точностью до регистра), по алфавиту языка телефона.
    static func города(_ товары: [Listing]) -> [String] {
        var виденные = Set<String>()
        var итог: [String] = []
        for товар in товары {
            let город = товар.city.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !город.isEmpty, виденные.insert(город.lowercased()).inserted else { continue }
            итог.append(город)
        }
        return итог.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

/// Лист «Уточнить»: правит уточнение модели сразу — сетка под листом отбирается на ходу, «Готово» просто закрывает.
struct ЛистУточнения: View {
    @ObservedObject var модель: FeedModel
    @Environment(\.dismiss) private var закрыть

    /// Своя инициализация: закрытое поле окружения сделало бы синтезированную недоступной из ленты.
    init(модель: FeedModel) {
        _модель = ObservedObject(wrappedValue: модель)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(String(format: RefineText.т("note"), модель.items.count), systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section {
                    Picker(RefineText.т("city"), selection: $модель.уточнение.город) {
                        Text(RefineText.т("any_city")).tag("")
                        ForEach(городаВыбора, id: \.self) { город in
                            Text(город).tag(город)
                        }
                    }
                }
                Section {
                    TextField(RefineText.т("from"), text: $модель.уточнение.ценаОт)
                        .keyboardType(.numberPad)
                    TextField(RefineText.т("to"), text: $модель.уточнение.ценаДо)
                        .keyboardType(.numberPad)
                } header: {
                    Text(RefineText.т("price"))
                } footer: {
                    if границыНаоборот { Text(RefineText.т("price_swapped")) }
                }
                Section {
                    Toggle(RefineText.т("only_new"), isOn: $модель.уточнение.толькоНовые)
                        .tint(Theme.green2)
                }
                Section {
                    Button(RefineText.т("reset"), role: .destructive) {
                        модель.уточнение = УточнениеЛенты()
                    }
                    .disabled(модель.уточнение.пустое)
                } footer: {
                    Text(итог)
                        .мерилоФормы()
                }
            }
            .navigationTitle(RefineText.т("title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(RefineText.т("done")) { закрыть() }
                }
            }
        }
        /* По высоте формы: без пустоты снизу, длинная — до полного. */
        .листПоВысоте()
    }

    /// Города загруженного и выбранный, даже если после обновления ленты его среди загруженного нет: Picker без
    /// строки для выбранного значения показал бы пустоту.
    private var городаВыбора: [String] {
        var список = УточнениеЛенты.города(модель.items)
        let выбран = модель.уточнение.город
        if !выбран.isEmpty && !список.contains(where: { $0.caseInsensitiveCompare(выбран) == .orderedSame }) {
            список.insert(выбран, at: 0)
        }
        return список
    }

    /// «от» больше «до» — ничего не подойдёт; подсказываем, а не молча показываем пустую ленту.
    private var границыНаоборот: Bool {
        guard let от = модель.уточнение.нижняя, let до = модель.уточнение.верхняя else { return false }
        return от > до
    }

    private var итог: String {
        String(format: RefineText.т("chip"), модель.видимые.count, модель.items.count)
    }
}

/// Кнопка «Уточнить» в полосе разделов — чипом той же формы; уточнено — залита, как выбранный раздел.
struct ЧипУточнения: View {
    let уточнено: Bool
    let действие: () -> Void

    var body: some View {
        Button(action: действие) {
            HStack(spacing: 6) {
                Image(systemName: уточнено ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(.system(size: 14, weight: .semibold))
                Text(RefineText.т("refine"))
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 13).padding(.vertical, 8)
            .foregroundStyle(уточнено ? Color.white : Theme.green2)
            .background(уточнено ? Theme.green2 : Color(.secondarySystemGroupedBackground), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(уточнено ? .isSelected : [])
    }
}

/// Строка над сеткой, пока лента уточнена: сколько подходит из загруженного. Нажатие — снова лист, крестик — сброс.
struct ПолосаУточнения: View {
    let видно: Int
    let загружено: Int
    let открыть: () -> Void
    let сбросить: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: открыть) {
                Label(String(format: RefineText.т("chip"), видно, загружено),
                      systemImage: "line.3.horizontal.decrease.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(Theme.green2)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 4)
            Button(action: сбросить) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(RefineText.т("reset_a11y"))
        }
        .padding(.leading, 12).padding(.trailing, 4).padding(.vertical, 4)
        .background(Theme.green2.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        .padding(.horizontal, 16)
    }
}
