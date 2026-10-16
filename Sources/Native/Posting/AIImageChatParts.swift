import SwiftUI
import UIKit

/**
 ОКНО «ИЛЛЮСТРАЦИЯ С ИИ» — РЕПЛИКИ.

 Человек — зелёный пузырь справа. ИИ — слева, со значком палочки:
   · ждём — карточка-заглушка без процентов (ответ идёт до пары минут): бегущее сияние, «Рисую иллюстрацию…»; связь
     оборвалась — «Связь прервалась — проверяю, готова ли картинка…»;
   · картинка — проявляется из размытия, плашка «Иллюстрация ИИ» (или подпись сервера label); «Взять в объявление»
     (взята — «В объявлении»), «Ещё вариант» и под ними — что это новый запуск;
   · отказ — текст сервера как есть и кнопки по случаю: «Повторить», «Собрать обложку без рисунка» (cover_ok),
     «Нарисовать с Kliko AI» (kliko_ok), «Свой ИИ».
 «Уменьшение движения» — без сияния и проявления; VoiceOver — подписи у картинок и кнопок.
 */
struct РепликаИИФотоВид: View {
    @ObservedObject var модель: МодельЧатаИИФото
    let реплика: РепликаИИФото

    init(модель: МодельЧатаИИФото, реплика: РепликаИИФото) {
        self.модель = модель
        self.реплика = реплика
    }

    var body: some View {
        switch реплика.кто {
        case .человек:
            ПузырьЧеловекаИИФото(реплика: реплика)
        case .ии:
            ОтветИИФотоВид(модель: модель, реплика: реплика)
        }
    }
}

// MARK: - Человек

struct ПузырьЧеловекаИИФото: View {
    let реплика: РепликаИИФото

    init(реплика: РепликаИИФото) {
        self.реплика = реплика
    }

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 56)
            Text(реплика.текст)
                .font(.body)
                .foregroundStyle(Color.white)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.пузырьМой,
                            in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18,
                                                       bottomTrailingRadius: 6, topTrailingRadius: 18,
                                                       style: .continuous))
                .accessibilityLabel(ИИФотоText.т("aim_you") + ": " + реплика.текст)
        }
    }
}

// MARK: - ИИ

struct ОтветИИФотоВид: View {
    @ObservedObject var модель: МодельЧатаИИФото
    let реплика: РепликаИИФото

    init(модель: МодельЧатаИИФото, реплика: РепликаИИФото) {
        self.модель = модель
        self.реплика = реплика
    }

    private func т(_ ключ: String) -> String { ИИФотоText.т(ключ) }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 30, height: 30)
                .background(LinearGradient(colors: [Theme.кнопкаКамерыНачало, Theme.кнопкаКамерыКонец],
                                           startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                содержимое
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var содержимое: some View {
        switch реплика.состояние {
        case .ждём:
            ЗаглушкаИИФото(прогресс: 0, подпись: т(реплика.проверяем ? "aim_stage_check" : "aim_stage_image"),
                           квадрат: true, проценты: false, ниже: реплика.проверяем ? "" : т("aim_stage_wait"))
        case .готово:
            if let итог = реплика.итог {
                КартинкаОтветаИИФото(модель: модель, реплика: реплика, итог: итог)
            }
        case .отказ:
            if let отказ = реплика.отказ {
                ОтказЧатаИИФото(модель: модель, реплика: реплика, отказ: отказ)
            }
        }
    }
}

// MARK: - Ожидание

/// Карточка-заглушка: мягкий зелёный фон, бегущее сияние, палочка, подпись (и, если нужно, проценты с полосой).
struct ЗаглушкаИИФото: View {
    let прогресс: Int
    let подпись: String
    let квадрат: Bool
    var проценты = true
    /// Строка под подписью («обычно до пары минут»); пусто — нет.
    var ниже = ""
    @State private var бег = false
    @Environment(\.accessibilityReduceMotion) private var меньшеДвижения

    init(прогресс: Int, подпись: String, квадрат: Bool, проценты: Bool = true, ниже: String = "") {
        self.прогресс = прогресс
        self.подпись = подпись
        self.квадрат = квадрат
        self.проценты = проценты
        self.ниже = ниже
    }

    private var тихо: Bool { меньшеДвижения || ДвижениеСайта.тихо }

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
        return ZStack {
            LinearGradient(colors: [КраскаПодачи.хорошоФон, КраскаПодачи.поле, КраскаПодачи.хорошоФон],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            сияние
            VStack(spacing: 10) {
                Image(systemName: "wand.and.stars")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(КраскаПодачи.хорошоТекст)
                    .symbolEffect(.pulse, isActive: !тихо)
                    .accessibilityHidden(true)
                if проценты {
                    Text(String(прогресс) + "%")
                        .font(.title2.weight(.heavy).monospacedDigit())
                        .foregroundStyle(КраскаПодачи.текст)
                        .contentTransition(.numericText())
                }
                Text(подпись)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(КраскаПодачи.текст)
                    .multilineTextAlignment(.center)
                if !ниже.isEmpty {
                    Text(ниже)
                        .font(.caption)
                        .foregroundStyle(Theme.текстВторой)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if проценты {
                    ProgressView(value: Double(прогресс), total: 100)
                        .tint(Theme.зелёный2)
                        .frame(maxWidth: 180)
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: квадрат ? nil : 150)
        .aspectRatio(квадрат ? 1 : nil, contentMode: .fit)
        .clipShape(форма)
        .overlay { форма.strokeBorder(КраскаПодачи.хорошоТекст.opacity(0.22), lineWidth: 1) }
        .onAppear {
            guard !тихо else { return }
            бег = true
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ниже.isEmpty ? подпись : подпись + ". " + ниже)
        .accessibilityValue(проценты ? String(format: ИИФотоText.т("aim_progress_a11y"), прогресс) : "")
        .accessibilityAddTraits(.updatesFrequently)
    }

    private static let бегСияния = Animation.linear(duration: 1.5).repeatForever(autoreverses: false)

    private var сияние: some View {
        GeometryReader { г in
            LinearGradient(colors: [Color.white.opacity(0), Color.white.opacity(0.5), Color.white.opacity(0)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: г.size.width * 0.45)
                .rotationEffect(.degrees(16))
                .offset(x: бег ? г.size.width * 1.2 : -г.size.width * 0.7)
                .animation(бег ? Self.бегСияния : nil, value: бег)
        }
        .opacity(тихо ? 0 : 0.55)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Картинка проявляется из размытия (при «Уменьшении движения» — сразу).
struct ПроявлениеИИФото: ViewModifier {
    @State private var видно = false
    @Environment(\.accessibilityReduceMotion) private var меньшеДвижения

    func body(content: Content) -> some View {
        let готово = видно || меньшеДвижения || ДвижениеСайта.тихо
        return content
            .opacity(готово ? 1 : 0)
            .blur(radius: готово ? 0 : 18)
            .scaleEffect(готово ? 1 : 1.03)
            .onAppear {
                guard !видно else { return }
                withAnimation(ДвижениеСайта.мягко(.easeOut(duration: 0.7))) { видно = true }
            }
    }
}

// MARK: - Картинка ответа

/// Готовая картинка с плашкой и действиями: «Взять в объявление», «Ещё вариант» и что это новый запуск.
struct КартинкаОтветаИИФото: View {
    @ObservedObject var модель: МодельЧатаИИФото
    let реплика: РепликаИИФото
    let итог: ИтогИИФото
    @ObservedObject private var готовность = ГотовностьИИФото.shared

    init(модель: МодельЧатаИИФото, реплика: РепликаИИФото, итог: ИтогИИФото) {
        self.модель = модель
        self.реплика = реплика
        self.итог = итог
    }

    private func т(_ ключ: String) -> String { ИИФотоText.т(ключ) }

    /// «Ещё вариант» — новый запуск; тратит месячный остаток — сказать и об этом.
    private var заметкаВарианта: String {
        т(готовность.сведения?.тратит == true ? "aim_again_note_spends" : "aim_again_note")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let картинка = реплика.картинка {
                КадрИИФото(картинка: картинка, вид: итог.вид, метка: итог.метка)
            } else {
                ЗаметкаПодачи(т("aim_err_image"), тон: .серый, значок: "photo")
            }
            if реплика.своимИИ {
                Text(СвойИИText.т("oai_via"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(КраскаПодачи.хорошоТекст)
            }
            ПотокЧипов(зазор: 8) {
                if реплика.взята {
                    ОтметкаВзятоИИФото(текст: т("aim_in_listing"))
                } else {
                    КнопкаЧатаИИФото(т("aim_take"), значок: "square.and.arrow.down", главная: true,
                                     занято: модель.берём) {
                        модель.взять(реплика.id)
                    }
                }
                КнопкаЧатаИИФото(т("aim_again"), значок: "arrow.triangle.2.circlepath") {
                    модель.ещёВариант(реплика.id)
                }
                .disabled(модель.идёт)
            }
            Text(заметкаВарианта)
                .font(.caption)
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Кадр с плашкой «Иллюстрация ИИ» / «Обложка ИИ» (или подписью сервера); пропорции — картинки.
struct КадрИИФото: View {
    let картинка: UIImage
    let вид: String
    /// label сервера; пусто — своя подпись вида.
    var метка = ""

    init(картинка: UIImage, вид: String, метка: String = "") {
        self.картинка = картинка
        self.вид = вид
        self.метка = метка
    }

    private var пропорция: CGFloat {
        let р = картинка.size
        guard р.width > 0, р.height > 0 else { return 1 }
        return max(0.5, min(1.8, р.width / р.height))
    }

    private var подпись: String { метка.isEmpty ? ПометкаИИФото.текст(вид) : метка }

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
        return Color.clear
            .aspectRatio(пропорция, contentMode: .fit)
            .overlay {
                Image(uiImage: картинка)
                    .resizable()
                    .scaledToFill()
            }
            .clipShape(форма)
            .overlay { форма.strokeBorder(КраскаПодачи.линия, lineWidth: 1) }
            .overlay(alignment: .topLeading) {
                if метка.isEmpty {
                    ПометкаИИФото(вид: вид, мелкая: false)
                        .padding(10)
                } else {
                    Text(метка)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.white)
                        .lineLimit(2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.62), in: Capsule())
                        .padding(10)
                }
            }
            .modifier(ПроявлениеИИФото())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(подпись)
            .accessibilityAddTraits(.isImage)
    }
}

// MARK: - Отказ

struct ОтказЧатаИИФото: View {
    @ObservedObject var модель: МодельЧатаИИФото
    let реплика: РепликаИИФото
    let отказ: ОтказИИФото
    /// Товары App Store: пришли — «Расширить лимит» под отказом slots_full встаёт сама.
    @ObservedObject private var покупки = ПокупкиApple.shared

    init(модель: МодельЧатаИИФото, реплика: РепликаИИФото, отказ: ОтказИИФото) {
        self.модель = модель
        self.реплика = реплика
        self.отказ = отказ
    }

    private func т(_ ключ: String) -> String { ИИФотоText.т(ключ) }

    private var значок: String {
        switch отказ.код {
        case "cap", "rate_limited", "slots_full": return "clock.badge.exclamationmark"
        case "net": return "wifi.exclamationmark"
        case "slow": return "hourglass"
        case "banned", "ai_blocked", "unsafe", "text_bad", "text_link", "letters", "imp": return "hand.raised.fill"
        default: return "exclamationmark.triangle.fill"
        }
    }

    /// Картинка ещё может прийти — «Проверить ещё раз» вместо нового запуска.
    private var ждём: Bool { реплика.ждатьКлюч != nil }

    /**
     slots_full — нет места под новое объявление: «Расширить лимит» (App Store: слоты, комбо или PRO), после покупки —
     тот же запрос картинки ещё раз (владелец 16.10.2026: «в окне предлагать расширить сразу»). cap (картинки на
     период), rate_limited и busy не продаются — там честная фраза без кнопки.
     */
    private var расширить: Bool {
        отказ.код == "slots_full" && реплика.повтор != nil && РасширениеЛимита.есть(РасширениеЛимита.слоты)
    }

    private var естьКнопки: Bool {
        ждём || (отказ.повторить && реплика.повтор != nil) || отказ.обложкаМожно || отказ.klikoМожно
            || отказ.свойИИ != nil || расширить
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: значок)
                    .foregroundStyle(Theme.оранжевый)
                    .accessibilityHidden(true)
                Text(отказ.текст)
                    .font(.subheadline)
                    .foregroundStyle(КраскаПодачи.текст)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(КраскаПодачи.вниманиеФон, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                    .strokeBorder(КраскаПодачи.вниманиеКромка, lineWidth: 1)
            }
            .accessibilityElement(children: .combine)
            if естьКнопки { кнопки }
        }
    }

    private var кнопки: some View {
        ПотокЧипов(зазор: 8) {
            if расширить {
                КнопкаРасширения(цепочка: РасширениеЛимита.слоты, действие: { вид in
                    let номер = реплика.id
                    ЛистУслугиApple.показать(вид, готово: { модель.повторить(номер) })
                }) { занято, нажать in
                    КнопкаЧатаИИФото(ЛимитText.т("lu_expand"), значок: "square.stack.3d.up", главная: true,
                                     занято: занято, действие: нажать)
                }
                .disabled(модель.идёт)
            }
            if ждём {
                КнопкаЧатаИИФото(т("aim_check_again"), значок: "arrow.clockwise", главная: true) {
                    модель.проверитьСнова(реплика.id)
                }
                .disabled(модель.идёт)
            } else if отказ.повторить && реплика.повтор != nil {
                КнопкаЧатаИИФото(т("aim_retry"), значок: "arrow.clockwise", главная: true) {
                    модель.повторить(реплика.id)
                }
                .disabled(модель.идёт)
            }
            if отказ.обложкаМожно && реплика.повтор != nil {
                КнопкаЧатаИИФото(т("aim_cover_btn"), значок: "rectangle.on.rectangle") {
                    модель.обложкаБезРисунка(реплика.id)
                }
                .disabled(модель.идёт)
            }
            if отказ.klikoМожно {
                КнопкаЧатаИИФото(т("aim_kliko_btn"), значок: "wand.and.stars") {
                    модель.нарисоватьKliko(реплика.id)
                }
                .disabled(модель.идёт)
            }
            if let свой = отказ.свойИИ {
                КнопкаЧатаИИФото(т("aim_own_ai"), значок: "cpu") { ОкноСвоегоИИ.показатьОтказ(свой) }
            }
        }
    }
}

// MARK: - Кнопки

/// Кнопка-капсула под ответом: главная — зелёная заливка, остальные — мятные; занята — колёсико.
struct КнопкаЧатаИИФото: View {
    let заголовок: String
    let значок: String
    var главная = false
    var занято = false
    let действие: () -> Void
    @Environment(\.isEnabled) private var доступна

    init(_ заголовок: String, значок: String, главная: Bool = false, занято: Bool = false,
         действие: @escaping () -> Void) {
        self.заголовок = заголовок
        self.значок = значок
        self.главная = главная
        self.занято = занято
        self.действие = действие
    }

    var body: some View {
        Button(action: действие) {
            HStack(spacing: 6) {
                if занято {
                    ProgressView()
                        .controlSize(.small)
                        .tint(главная ? Color.white : Theme.зелёный2)
                } else {
                    Image(systemName: значок)
                        .font(.footnote.weight(.semibold))
                        .accessibilityHidden(true)
                }
                Text(заголовок)
                    .font(.footnote.weight(.bold))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
            }
            .foregroundStyle(главная ? Color.white : КраскаПодачи.хорошоТекст)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minHeight: 36)
            .background(главная ? AnyShapeStyle(Theme.зелёный2) : AnyShapeStyle(КраскаПодачи.хорошоФон), in: Capsule())
            .opacity(доступна ? 1 : 0.5)
            .contentShape(Capsule())
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.95))
        .disabled(занято)
    }
}

/// «В объявлении ✓» вместо кнопки, когда картинку уже взяли.
struct ОтметкаВзятоИИФото: View {
    let текст: String

    init(текст: String) {
        self.текст = текст
    }

    var body: some View {
        Label(текст, systemImage: "checkmark.circle.fill")
            .font(.footnote.weight(.bold))
            .foregroundStyle(КраскаПодачи.хорошоТекст)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minHeight: 36)
            .background(КраскаПодачи.хорошоФон, in: Capsule())
    }
}
