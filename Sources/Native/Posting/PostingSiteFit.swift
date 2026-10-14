import SwiftUI

/**
 «ЗАМЕРЫ ВЕЩИ» В ПОДАЧЕ (сайт 14.10.2026, «Подойдёт ли размер?», рубильник fit_help).

 Когда в схеме подачи rules.fit.on = true, а раздел формы есть в rules.fit.cats (вверх по дереву), на шаге
 «Характеристики» — свёрнутый необязательный блок «Замеры вещи»: при «ask» сначала выбор вида (верх, низ, платье,
 верхняя одежда), потом замеры вида в сантиметрах (ширины — по лежащей вещи от шва до шва, половина обхвата) с
 пределами из range. В submit уходит fit = {kind?, ключ: число}; в правке — только если замеры трогали (пустой fit
 снимает их), значения подставляются из my_items. Сервер сам чистит значения по пределам и разделу.
 */
struct БлокЗамеровПодачи: View {
    @ObservedObject var модель: ПодачаМодель
    let фокус: FocusState<String?>.Binding

    init(модель: ПодачаМодель, фокус: FocusState<String?>.Binding) {
        self.модель = модель
        self.фокус = фокус
    }

    private func т(_ ключ: String) -> String { ПодачаСайтаText.т(ключ) }

    private let колонки = [GridItem(.flexible(), spacing: 10, alignment: .top), GridItem(.flexible(), spacing: 10, alignment: .top)]

    var body: some View {
        if let правила = модель.схема?.замеры, let назначено = модель.видЗамеровРаздела {
            блок(правила, назначено)
        }
    }

    private func блок(_ правила: ПравилаЗамеровВещи, _ назначено: String) -> some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            шапка(правила)
            if модель.замерыОткрыты {
                VStack(alignment: .leading, spacing: 12) {
                    ПодсказкаПоля(правила.подсказка.isEmpty ? т("fit_hint") : правила.подсказка)
                    if назначено == "ask" { выборВида(правила) }
                    if !модель.ключиЗамеров.isEmpty { поля(правила) }
                    if !правила.как.isEmpty {
                        ЗаметкаПодачи(правила.как, тон: .серый, значок: "ruler")
                    }
                }
                .padding(.top, 12)
                .transition(.opacity)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(КраскаПодачи.карточка, in: форма)
        .overlay { форма.strokeBorder(КраскаПодачи.линия, lineWidth: 1) }
        .onAppear {
            /* Замеры уже есть (правка, черновик) — блок сразу раскрыт. */
            if let замеры = модель.форма.замеры, !замеры.пусто { модель.замерыОткрыты = true }
        }
        .id("fit")
    }

    /// Заголовок-кнопка: линейка, «Замеры вещи · необязательно», пояснение и стрелка.
    private func шапка(_ правила: ПравилаЗамеровВещи) -> some View {
        Button {
            фокус.wrappedValue = nil
            withAnimation(ДвижениеСайта.смена) { модель.замерыОткрыты.toggle() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "ruler")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.акцент)
                    .frame(width: 33, height: 33)
                    .background(Theme.оттенокАкцента, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(правила.заголовок.isEmpty ? т("fit_title") : правила.заголовок)
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(КраскаПодачи.текст)
                        Text("· " + ПодачаText.т("form_optional"))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.текстВторой)
                    }
                    Text(т("fit_sub"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: модель.замерыОткрыты ? "chevron.up" : "chevron.down")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.текстВторой)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isHeader)
        .accessibilityAddTraits(модель.замерыОткрыты ? .isSelected : [])
    }

    /// «ask»: что это за вещь — чипы видов; другой вид — значения прежнего вида уходят.
    private func выборВида(_ правила: ПравилаЗамеровВещи) -> some View {
        let выбран = модель.форма.замеры?.вид ?? ""
        return VStack(alignment: .leading, spacing: 6) {
            ПодписьПоля(т("fit_kind"), мелкая: true)
            ПотокЧипов(зазор: 8) {
                ForEach(правила.выбор, id: \.self) { вид in
                    ЧипПодачи(правила.подписьВида(вид), выбран: выбран == вид) {
                        выбратьВид(вид)
                    }
                }
            }
        }
    }

    private func выбратьВид(_ вид: String) {
        var замеры = модель.форма.замеры ?? ЗамерыВещиПодачи()
        guard замеры.вид != вид else { return }
        замеры.вид = вид
        замеры.значения = [:]
        ОткликСайта.выбор()
        модель.форма.замеры = замеры
    }

    /// Замеры вида по два в ряд: подпись, поле «от–до» в см.
    private func поля(_ правила: ПравилаЗамеровВещи) -> some View {
        LazyVGrid(columns: колонки, alignment: .leading, spacing: 12) {
            ForEach(модель.ключиЗамеров, id: \.self) { ключ in
                VStack(alignment: .leading, spacing: 6) {
                    ПодписьПоля(правила.подписьЗамера(ключ), мелкая: true)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    ПолеПодачи(подсказка(правила, ключ), текст: значение(ключ), клавиатура: .decimalPad,
                               фокус: фокус, ключ: "fit_" + ключ, единица: т("fit_cm"))
                }
                .id("fit_" + ключ)
            }
        }
    }

    /// «40–70» по range сайта; нет предела — «см».
    private func подсказка(_ правила: ПравилаЗамеровВещи, _ ключ: String) -> String {
        guard let предел = правила.пределы[ключ] else { return т("fit_cm") }
        return ЗамерыВещиПодачи.строкаЧисла(предел.от) + "–" + ЗамерыВещиПодачи.строкаЧисла(предел.до)
    }

    /// Значение замера: цифры и одна дробная часть (запятая или точка), не длиннее 6 знаков.
    private func значение(_ ключ: String) -> Binding<String> {
        let м = модель
        return Binding(get: { м.форма.замеры?.значения[ключ] ?? "" }, set: { новое in
            let чистое = ПодачаМодель.дробное(новое, предел: 6)
            var замеры = м.форма.замеры ?? ЗамерыВещиПодачи()
            if чистое.isEmpty {
                замеры.значения.removeValue(forKey: ключ)
            } else {
                замеры.значения[ключ] = чистое
            }
            if м.форма.замеры != замеры { м.форма.замеры = замеры }
        })
    }
}
