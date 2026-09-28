import SwiftUI

/**
 ДЕТАЛИ ЭКРАНОВ ПОТОКА eGov — по css_cabinet.css сайта: .bio-note, .bio-lbl, .inp, .bio-warn, .bio-sub, .egov-agree,
 .btn.btn-g, .bio-dlg (значок .bio-dlg-badge.ok / .err, кнопки .bio-dlg-btn.ok / .err, .bio-dlg-ghost).
 */
enum КраскаEgov {
    /// Фон листа кабинета.
    static let фон = Theme.цвет(0xEEF3F0, 0x101017)
    /// --card.
    static let карточка = Theme.цвет(0xFFFFFF, 0x1C1C26)
    /// --line.
    static let линия = Theme.цвет(светлый: Theme.hex(0xE6EFE9), тёмный: Theme.hex(0xFFFFFF, 0.10))
    /// --on-ok: замок .bio-sub, ссылки согласия.
    static let хорошо = Theme.цвет(0x0F7A44, 0x5CD39A)
    /// --red: строка ошибки формы.
    static let плохо = Theme.цвет(0xC0392B, 0xFF6168)
    /// .bio-succ-btn / .bio-dlg-btn.ok: #1d9e5e → #12703f.
    static let зелёныйНачало = Color(uiColor: Theme.hex(0x1D9E5E))
    static let зелёныйКонец = Color(uiColor: Theme.hex(0x12703F))
    /// .bio-dlg-btn.err: #ef5350 → #c62828.
    static let красныйНачало = Color(uiColor: Theme.hex(0xEF5350))
    static let красныйКонец = Color(uiColor: Theme.hex(0xC62828))
    /// .bio-dlg-badge.ok: radial #2fd07a → #12703f; .err: #ff6f61 → #c62828.
    static let значокХорошоСвет = Color(uiColor: Theme.hex(0x2FD07A))
    static let значокПлохоСвет = Color(uiColor: Theme.hex(0xFF6F61))
    /// Тень зелёной кнопки: rgba(18,112,63,.75).
    static let теньЗелёная = Color(red: 18 / 255, green: 112 / 255, blue: 63 / 255)
    static let теньКрасная = Color(red: 198 / 255, green: 40 / 255, blue: 40 / 255)
}

/// Кнопки окна eGov: главная (.btn-g), успех (.bio-dlg-btn.ok), ошибка (.bio-dlg-btn.err), тихая (.bio-dlg-ghost).
enum ВидКнопкиEgov {
    case главная
    case успех
    case ошибка
    case тихая
}

struct КнопкаEgov: View {
    let подпись: String
    var вид: ВидКнопкиEgov = .главная
    var идёт = false
    let действие: () -> Void

    private var краски: [Color] {
        switch вид {
        case .главная: return [Theme.зелёный, Theme.зелёный2]
        case .успех: return [КраскаEgov.зелёныйНачало, КраскаEgov.зелёныйКонец]
        case .ошибка: return [КраскаEgov.красныйНачало, КраскаEgov.красныйКонец]
        case .тихая: return [Color.clear, Color.clear]
        }
    }

    private var тень: Color {
        switch вид {
        case .главная, .успех: return КраскаEgov.теньЗелёная
        case .ошибка: return КраскаEgov.теньКрасная
        case .тихая: return Color.clear
        }
    }

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
        Button(action: действие) {
            ZStack {
                if идёт {
                    SiteSpinner(размер: 20, толщина: 2.5, дорожка: Color.white.opacity(0.35), верх: Color.white)
                } else {
                    Text(подпись)
                        .font(.system(size: вид == .тихая ? 15 : 16, weight: вид == .тихая ? .bold : .heavy))
                        .foregroundStyle(вид == .тихая ? Theme.текстВторой : Color.white)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background {
                форма.fill(LinearGradient(colors: краски, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: тень.opacity(0.45), radius: 8, y: 6)
            }
            .overlay {
                if вид == .тихая {
                    форма.strokeBorder(КраскаEgov.линия, lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
        .disabled(идёт)
        .accessibilityLabel(подпись)
    }
}

/// Индикатор шагов: «Данные» → «eGov» → «Готово»; сбой — второй шаг красным.
struct ШагиEgov: View {
    let текущий: Int
    let сбой: Bool

    private var подписи: [String] { ["step_data", "step_egov", "step_done"] }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { номер in
                пункт(номер)
                if номер < 2 {
                    Capsule()
                        .fill(номер < текущий ? КраскаEgov.хорошо : КраскаEgov.линия)
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.horizontal, 4)
        .animation(ДвижениеСайта.шаг, value: текущий)
    }

    private func пункт(_ номер: Int) -> some View {
        let пройден = номер < текущий || (номер == 2 && текущий == 2)
        let сейчас = номер == текущий && !пройден
        let плохо = сейчас && сбой
        let краска: Color = плохо ? КраскаEgov.плохо : ((пройден || сейчас) ? КраскаEgov.хорошо : Theme.текстВторой)
        return HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(пройден ? краска : Color.clear)
                Circle()
                    .strokeBorder(краска, lineWidth: 1.5)
                if пройден {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Color.white)
                } else {
                    Text(verbatim: String(номер + 1))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(краска)
                }
            }
            .frame(width: 22, height: 22)
            Text(ТекстыEgov.т(подписи[номер]))
                .font(.system(size: 12, weight: сейчас ? .bold : .semibold))
                .foregroundStyle(сейчас || пройден ? Theme.текст : Theme.текстВторой)
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(сейчас ? .isSelected : [])
    }
}

/// Белая карточка окна (.cmp-pick-box): радиус 18, рамка --line.
struct КарточкаEgov<Содержимое: View>: View {
    @ViewBuilder let содержимое: () -> Содержимое

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
        содержимое()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(КраскаEgov.карточка, in: форма)
            .overlay { форма.strokeBorder(КраскаEgov.линия, lineWidth: 1) }
    }
}

/// .bio-note: 14, --muted, lh 1.5; с символом слева.
struct ЗаметкаEgov: View {
    let текст: String
    var символ = "faceid"

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: символ)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(КраскаEgov.хорошо)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(текст)
                .font(.system(size: 14))
                .lineSpacing(4)
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// «Как это пройдёт»: три шага, второй — на экране eGov.
struct КакЭтоEgov: View {
    var body: some View {
        КарточкаEgov {
            VStack(alignment: .leading, spacing: 12) {
                Text(ТекстыEgov.т("why"))
                    .font(.system(size: 14))
                    .lineSpacing(4)
                    .foregroundStyle(Theme.текст)
                    .fixedSize(horizontal: false, vertical: true)
                Text(ТекстыEgov.т("how_t"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.текстВторой)
                пункт(1, символ: "person.text.rectangle", "how1_t", "how1_s")
                пункт(2, символ: "faceid", "how2_t", "how2_s")
                пункт(3, символ: "checkmark.seal", "how3_t", "how3_s")
            }
        }
    }

    private func пункт(_ номер: Int, символ: String, _ заголовок: String, _ подпись: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: символ)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(КраскаEgov.хорошо)
                .frame(width: 34, height: 34)
                .background(КраскаСделокКабинета.хорошоФон, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(ТекстыEgov.т(заголовок))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.текст)
                Text(ТекстыEgov.т(подпись))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: String(номер) + ". " + ТекстыEgov.т(заголовок) + ". " + ТекстыEgov.т(подпись)))
    }
}

/// .bio-lbl над полем .inp: подпись 13/700 --muted, поле 48, радиус 12, рамка 1,5 (в фокусе — зелёная).
struct ПолеEgov<Содержимое: View>: View {
    let подпись: String
    var пометка: String? = nil
    let вФокусе: Bool
    @ViewBuilder let содержимое: () -> Содержимое

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
        VStack(alignment: .leading, spacing: 6) {
            (Text(подпись).bold() + Text(verbatim: пометка.map { " " + $0 } ?? "").fontWeight(.regular))
                .font(.system(size: 13))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
            содержимое()
                .font(.system(size: 17, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.текст)
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(КраскаEgov.карточка, in: форма)
                .overlay {
                    форма.strokeBorder(вФокусе ? Theme.зелёный2 : КраскаEgov.линия, lineWidth: 1.5)
                }
                .environment(\.layoutDirection, .leftToRight)
        }
    }
}

/// .bio-warn: жёлтая плашка с треугольником.
struct ПредупреждениеEgov: View {
    let текст: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 14, weight: .semibold))
                .accessibilityHidden(true)
            Text(текст)
                .font(.system(size: 13, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(КраскаСделокКабинета.предупреждениеТекст)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(КраскаСделокКабинета.предупреждениеФон, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                .strokeBorder(КраскаСделокКабинета.предупреждениеКромка, lineWidth: 1)
        }
    }
}

/// .bio-sub: замок --on-ok и «Данные передаются в зашифрованном виде…», 12, --muted.
struct ЗамокEgov: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(КраскаEgov.хорошо)
                .padding(.top, 1)
                .accessibilityHidden(true)
            Text(ТекстыEgov.т("sec_note"))
                .font(.system(size: 12))
                .lineSpacing(3)
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// .egov-agree: чекбокс и «Я прочитал(а) и принимаю …» со ссылками — тот же текст, что у регистрации.
struct СогласиеEgov: View {
    @Binding var принято: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                принято.toggle()
            } label: {
                Image(systemName: принято ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22))
                    .foregroundStyle(принято ? Theme.зелёный2 : Theme.текстВторой)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ВходText.т("auth_terms_link"))
            .accessibilityAddTraits(принято ? .isSelected : [])
            Text(ТекстСогласия.строка(ВходText.т("auth_agree"), размер: 13))
                .font(.system(size: 13))
                .lineSpacing(5)
                .foregroundStyle(Theme.текст)
                .tint(КраскаEgov.хорошо)
                .fixedSize(horizontal: false, vertical: true)
                .environment(\.openURL, ТекстСогласия.открыватель)
        }
    }
}

/// Строка сверки «ИИН … 000000000000» (boostConfirm сайта): подпись --muted, значение жирным, моноширинные цифры.
struct СтрокаСверкиEgov: View {
    let подпись: String
    let значение: String

    var body: some View {
        HStack(spacing: 10) {
            Text(подпись)
                .font(.system(size: 14))
                .foregroundStyle(Theme.текстВторой)
            Spacer(minLength: 8)
            Text(verbatim: значение)
                .font(.system(size: 16, weight: .bold).monospacedDigit())
                .foregroundStyle(Theme.текст)
                .environment(\.layoutDirection, .leftToRight)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            Rectangle().fill(КраскаEgov.линия).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Кольцо отсчёта окна подтверждения: доля оставшегося и «м:сс» в середине.
struct КольцоОжиданияEgov: View {
    let осталось: Int
    let всего: Int

    var body: some View {
        let доля = всего > 0 ? max(0, min(1, Double(осталось) / Double(всего))) : 0
        let с = max(0, осталось)
        ZStack {
            Circle()
                .stroke(КраскаEgov.линия, lineWidth: 6)
            Circle()
                .trim(from: 0, to: доля)
                .stroke(осталось <= 60 ? КраскаEgov.плохо : КраскаEgov.хорошо,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(ДвижениеСайта.прогресс, value: доля)
            Text(verbatim: String(с / 60) + ":" + String(format: "%02d", с % 60))
                .font(.system(size: 24, weight: .heavy).monospacedDigit())
                .foregroundStyle(Theme.текст)
        }
        .frame(width: 112, height: 112)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: String(с / 60) + ":" + String(format: "%02d", с % 60)))
    }
}

/// .bio-dlg-badge: круг 92 с радиальной заливкой, галочка или «!» рисуются, как у сайта (bioRing, bioCheck).
struct ЗначокИтогаEgov: View {
    let удача: Bool
    @State private var нарисован = false

    var body: some View {
        let свет = удача ? КраскаEgov.значокХорошоСвет : КраскаEgov.значокПлохоСвет
        let тень = удача ? КраскаEgov.зелёныйКонец : КраскаEgov.красныйКонец
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [свет, тень], center: UnitPoint(x: 0.32, y: 0.26),
                                     startRadius: 0, endRadius: 70))
                .shadow(color: тень.opacity(0.55), radius: 14, y: 12)
            Circle()
                .trim(from: 0, to: нарисован ? 1 : 0)
                .stroke(Color.white.opacity(0.55), lineWidth: 3)
                .rotationEffect(.degrees(-90))
                .padding(14)
            знак
        }
        .frame(width: 92, height: 92)
        .scaleEffect(нарисован ? 1 : 0.8)
        .onAppear {
            withAnimation(ДвижениеСайта.мягко(.spring(response: 0.38, dampingFraction: 0.62))) { нарисован = true }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var знак: some View {
        if удача {
            ГалочкаEgov()
                .trim(from: 0, to: нарисован ? 1 : 0)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                .frame(width: 38, height: 30)
                .animation(ДвижениеСайта.мягко(.easeOut(duration: 0.45).delay(0.3)), value: нарисован)
        } else {
            Image(systemName: "exclamationmark")
                .font(.system(size: 38, weight: .heavy))
                .foregroundStyle(Color.white)
                .opacity(нарисован ? 1 : 0)
        }
    }
}

/// Галочка .bio-dlg-k: две линии.
struct ГалочкаEgov: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.36, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        return p
    }
}
