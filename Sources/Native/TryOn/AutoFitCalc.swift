import SwiftUI

/**
 «ПОДОЙДУТ ЛИ?» — КАЛЬКУЛЯТОР РАЗМЕРА ШИН («Сравнить размеры», владелец 13.10.2026: «нужнее охват всего»).

 Два размера — «было» (штатные шины машины) и «стало» (новые): ширина, профиль и диаметр выбираются меню. Ниже —
 рисунок двух колёс, стоящих на одной земле (новое залито, штатное — пунктиром: видно, насколько выше или ниже), и
 числа: внешний диаметр, высота профиля, ширина, что покажет спидометр при 60 и 100 км/ч, клиренс. Норма — отличие
 внешнего диаметра до ±3 % (СравнениеШинАвтоподбора, AutoFitMath.swift): зелёная отметка или оранжевое предупреждение.
 Всё на телефоне. Рисунок для VoiceOver — одной фразой; числа читаются строками.
 */
struct КалькуляторАвтоподбора: View {
    @State private var было: РазмерШиныАвтоподбора
    @State private var стало: РазмерШиныАвтоподбора

    init(было: РазмерШиныАвтоподбора, стало: РазмерШиныАвтоподбора) {
        _было = State(initialValue: было)
        _стало = State(initialValue: стало)
    }

    private func т(_ ключ: String) -> String { АвтоподборText.т(ключ) }

    private func ф(_ ключ: String, _ аргументы: String...) -> String {
        String(format: т(ключ), arguments: аргументы.map { $0 as CVarArg })
    }

    private var с: СравнениеШинАвтоподбора { СравнениеШинАвтоподбора(было: было, стало: стало) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text(т("af_calc_hint"))
                    .font(.subheadline)
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ВыборРазмераАвтоподбора(заголовок: т("af_calc_old"), размер: $было)
                обмен
                ВыборРазмераАвтоподбора(заголовок: т("af_calc_new"), размер: $стало)
                рисунок
                отметка
                итоги
            }
            .padding(16)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .navigationTitle(т("af_calc_title"))
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: стало)
        .sensoryFeedback(.selection, trigger: было)
    }

    /// Поменять «было» и «стало» местами.
    private var обмен: some View {
        Button {
            let прежнее = было
            было = стало
            стало = прежнее
        } label: {
            Label(т("af_calc_swap"), systemImage: "arrow.up.arrow.down")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.акцент)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(Theme.оттенокАкцента, in: Capsule())
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.95))
    }

    private var рисунок: some View {
        VStack(spacing: 8) {
            РисунокШинАвтоподбора(было: было, стало: стало)
                .frame(height: 170)
            HStack(spacing: 16) {
                легенда(т("af_calc_old_short"), пунктир: true)
                легенда(т("af_calc_new_short"), пунктир: false)
            }
        }
        .карточкаАвтоподбора()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(подписьРисунка)
    }

    private var подписьРисунка: String {
        if abs(с.клиренс) < 0.5 { return т("af_calc_pic_same") }
        return ф(с.клиренс > 0 ? "af_calc_pic_up" : "af_calc_pic_down", ЧислаАвтоподбора.ч(abs(с.клиренс), знаков: 0))
    }

    private func легенда(_ текст: String, пунктир: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .stroke(Theme.акцент, style: StrokeStyle(lineWidth: 2, dash: пунктир ? [3, 3] : []))
                .background(Circle().fill(пунктир ? Color.clear : Theme.текст.opacity(0.85)))
                .frame(width: 14, height: 14)
            Text(текст)
                .font(.footnote)
                .foregroundStyle(Theme.текстВторой)
        }
    }

    /// В норме ±3 % или нет — цветом и словами.
    private var отметка: some View {
        let уровень: УровеньАвтоподбора = с.вНорме ? .подходит : .проверить
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: уровень.значок)
                .font(.body.weight(.semibold))
                .foregroundStyle(уровень.краска)
                .accessibilityHidden(true)
            Text(т(с.вНорме ? "af_calc_ok" : "af_calc_bad"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.текст)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(уровень.краска.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var строки: [(подпись: String, значение: String)] {
        let ч = ЧислаАвтоподбора.ч
        let разница = ф("af_calc_diff", ЧислаАвтоподбора.соЗнаком(с.разницаМм, знаков: 0),
                        ЧислаАвтоподбора.соЗнаком(с.процент) + "%")
        let клиренс: String
        if abs(с.клиренс) < 0.5 {
            клиренс = т("af_clear_same")
        } else {
            клиренс = ф(с.клиренс > 0 ? "af_clear_up" : "af_clear_down", ч(abs(с.клиренс), 0))
        }
        return [
            (т("af_calc_outer"), ф("af_calc_arrow_mm", ч(было.внешний, 0), ч(стало.внешний, 0)) + " · " + разница),
            (т("af_calc_side"), ф("af_calc_arrow_mm", ч(было.боковина, 0), ч(стало.боковина, 0))),
            (т("af_calc_width_row"), ф("af_calc_arrow_mm", ч(было.ширина, 0), ч(стало.ширина, 0))),
            (ф("af_calc_speed", "60"), ф("af_speed_real", ч(с.скорость(60), 1))),
            (ф("af_calc_speed", "100"), ф("af_speed_real", ч(с.скорость(100), 1))),
            (т("af_row_clear"), клиренс)
        ]
    }

    private var итоги: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(строки.enumerated()), id: \.offset) { номер, строка in
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        подпись(строка.подпись)
                        Spacer(minLength: 8)
                        значение(строка.значение)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        подпись(строка.подпись)
                        значение(строка.значение)
                    }
                }
                .padding(.vertical, 10)
                .accessibilityElement(children: .combine)
                if номер < строки.count - 1 {
                    Divider()
                        .overlay(Theme.линия)
                }
            }
        }
        .карточкаАвтоподбора()
    }

    private func подпись(_ текст: String) -> some View {
        Text(текст)
            .font(.subheadline)
            .foregroundStyle(Theme.текстВторой)
    }

    private func значение(_ текст: String) -> some View {
        Text(текст)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.текст)
            .multilineTextAlignment(.trailing)
    }
}

// MARK: - Выбор размера

/// Карточка размера: заголовок («Было — штатные»), размер крупно и три меню — ширина, профиль, диаметр.
struct ВыборРазмераАвтоподбора: View {
    let заголовок: String
    @Binding var размер: РазмерШиныАвтоподбора

    init(заголовок: String, размер: Binding<РазмерШиныАвтоподбора>) {
        self.заголовок = заголовок
        _размер = размер
    }

    private func т(_ ключ: String) -> String { АвтоподборText.т(ключ) }

    /// Список значений с текущим (если его нет в шаге — например, ширина 240).
    private func значения(_ шаг: [Double], _ текущее: Double) -> [Double] {
        шаг.contains(текущее) ? шаг : (шаг + [текущее]).sorted()
    }

    private var ширины: [Double] { значения(stride(from: 125.0, through: 355.0, by: 10).map { $0 }, размер.ширина) }
    private var профили: [Double] { значения(stride(from: 25.0, through: 85.0, by: 5).map { $0 }, размер.профиль) }
    private var диаметры: [Double] { значения(stride(from: 12.0, through: 24.0, by: 1).map { $0 }, размер.диаметр) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(заголовок)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.акцент)
                    .textCase(.uppercase)
                Spacer(minLength: 8)
                Text(размер.подпись)
                    .font(.headline)
                    .foregroundStyle(Theme.текст)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 8) {
                    колонки
                }
                VStack(alignment: .leading, spacing: 8) {
                    колонки
                }
            }
        }
        .карточкаАвтоподбора()
    }

    @ViewBuilder
    private var колонки: some View {
        колонка(т("af_calc_width"), значения: ширины, выбор: $размер.ширина) { ЧислаАвтоподбора.ч($0) }
        колонка(т("af_calc_profile"), значения: профили, выбор: $размер.профиль) { ЧислаАвтоподбора.ч($0) }
        колонка(т("af_calc_diam"), значения: диаметры, выбор: $размер.диаметр) { "R" + ЧислаАвтоподбора.ч($0) }
    }

    private func колонка(_ подпись: String, значения: [Double], выбор: Binding<Double>,
                         запись: @escaping (Double) -> String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(подпись)
                .font(.caption)
                .foregroundStyle(Theme.текстВторой)
                .lineLimit(2)
                .accessibilityHidden(true)
            Menu {
                Picker(подпись, selection: выбор) {
                    ForEach(значения, id: \.self) { значение in
                        Text(запись(значение)).tag(значение)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(запись(выбор.wrappedValue))
                        .font(.body.weight(.bold))
                        .foregroundStyle(Theme.текст)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.акцент)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                        .strokeBorder(Theme.линия, lineWidth: 1)
                }
            }
            .accessibilityLabel(подпись)
            .accessibilityValue(запись(выбор.wrappedValue))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Рисунок

/**
 Два колеса сбоку на одной земле в одном масштабе: новое — тёмная шина и светлый диск, штатное — пунктиром акцентом.
 Разница видна честно, без преувеличения. Не зеркалится в RTL (это рисунок, а не текст).
 */
struct РисунокШинАвтоподбора: View {
    let было: РазмерШиныАвтоподбора
    let стало: РазмерШиныАвтоподбора

    var body: some View {
        Canvas { холст, место in
            let земля = место.height - 4
            let наибольший = max(было.внешний, стало.внешний, 1)
            let масштаб = max(0.01, (место.height - 12) / CGFloat(наибольший))
            let центрX = место.width / 2
            func круг(_ радиус: CGFloat, _ центрY: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: центрX - радиус, y: центрY - радиус, width: радиус * 2, height: радиус * 2))
            }
            var линия = Path()
            линия.move(to: CGPoint(x: 0, y: земля))
            линия.addLine(to: CGPoint(x: место.width, y: земля))
            холст.stroke(линия, with: .color(Theme.линия), lineWidth: 2)

            let шинаНовой = CGFloat(стало.внешний) * масштаб / 2
            let центрНовой = земля - шинаНовой
            let дискНовой = CGFloat(стало.диаметр * 25.4) * масштаб / 2
            холст.fill(круг(шинаНовой, центрНовой), with: .color(Theme.текст.opacity(0.85)))
            холст.fill(круг(дискНовой, центрНовой), with: .color(Theme.поверхность2))
            холст.stroke(круг(дискНовой, центрНовой), with: .color(Theme.текстВторой), lineWidth: 1.5)
            холст.fill(круг(дискНовой * 0.22, центрНовой), with: .color(Theme.текстВторой))

            let шинаШтатной = CGFloat(было.внешний) * масштаб / 2
            let центрШтатной = земля - шинаШтатной
            let дискШтатной = CGFloat(было.диаметр * 25.4) * масштаб / 2
            холст.stroke(круг(шинаШтатной, центрШтатной), with: .color(Theme.акцент),
                         style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
            холст.stroke(круг(дискШтатной, центрШтатной), with: .color(Theme.акцент.opacity(0.7)),
                         style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }
}
