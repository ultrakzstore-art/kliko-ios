import SwiftUI
import UIKit

/**
 ОКНО ПРИМЕРОЧНОЙ (владелец 13.10.2026: «примерочная для одежды»; «мощная анимированная подача», «удобно для глаз»).

 Студия всегда тёмная (как камера поиска и подачи): глубокий зелёно-чёрный фон с мягким свечением, белый текст, зелёный
 акцент. Шаги сменяются плавно (ДвижениеСайта.шаг); при «Уменьшении движения» — сразу. Состояние держит
 МодельПримерочной; здесь — корень, «Ваше фото» (проверка и согласие) и экраны «Войдите», «Скоро», «Не получилось».
 Съёмка — TryOnCamera.swift, ожидание — TryOnWait.swift, итог со шторкой — TryOnResult.swift. вид — что рисует ИИ
 (человек, машина, комната, ВидИИПримерки): от него подписи шагов и смысл отметки «люди в кадре».
 */
struct ЭкранПримерочной: View {
    let закрыть: () -> Void
    @StateObject private var модель: МодельПримерочной
    @StateObject private var камера = КамераПоиска()

    init(товар: Listing, номерФото: Int, вид: ВидИИПримерки = .человек, закрыть: @escaping () -> Void) {
        self.закрыть = закрыть
        _модель = StateObject(wrappedValue: МодельПримерочной(товар: товар, номерФото: номерФото, вид: вид))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ФонПримерочной()
            /* Своя метка у каждого шага: смена шага — новый вид, и он проявляется (переход в перейти модели). */
            шаг
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(модель.шаг)
                .transition(.opacity)
            if let весть = модель.весть {
                ВестьПримерочной(текст: весть)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .environment(\.colorScheme, .dark)
        .onAppear { модель.открыт() }
        .onDisappear { модель.закрыть() }
        .onChange(of: модель.шаг) { _, _ in
            UIAccessibility.post(notification: .screenChanged, argument: nil)
        }
    }

    @ViewBuilder
    private var шаг: some View {
        switch модель.шаг {
        case .фото:
            ШагСъёмкиПримерочной(модель: модель, камера: камера, закрыть: закрыть)
        case .проверка:
            ШагПроверкиПримерочной(модель: модель, закрыть: закрыть)
        case .ждём:
            ШагОжиданияПримерочной(модель: модель)
        case .готово:
            ШагИтогаПримерочной(модель: модель, закрыть: закрыть)
        case .отказ, .вход, .скоро:
            ШагОтказаПримерочной(модель: модель, закрыть: закрыть)
        }
    }
}

// MARK: - Общее оформление

/// Фон студии: почти чёрный зелёный и два мягких пятна света — сверху и снизу.
struct ФонПримерочной: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(uiColor: Theme.hex(0x07130D)), Color(uiColor: Theme.hex(0x0C1F16))],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Theme.зелёныйЯркий.opacity(0.22), Color.clear], center: .top,
                           startRadius: 10, endRadius: 420)
            RadialGradient(colors: [Color(uiColor: Theme.hex(0x1D7D4A)).opacity(0.18), Color.clear], center: .bottom,
                           startRadius: 10, endRadius: 360)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Короткая весть внизу окна: тёмное стекло, зелёная кромка.
struct ВестьПримерочной: View {
    let текст: String

    var body: some View {
        Text(текст)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.white)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay { Capsule().strokeBorder(Theme.зелёныйЯркий.opacity(0.55), lineWidth: 1) }
            .shadow(color: Color.black.opacity(0.35), radius: 12, x: 0, y: 6)
            .accessibilityHidden(true)
    }
}

/// Шапка шагов: ✕ слева, заголовок по центру; справа — место той же ширины (заголовок ровно по центру).
struct ШапкаПримерочной: View {
    let заголовок: String
    let закрыть: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            КруглаяКнопкаФото(значок: "xmark", подпись: ПримерочнаяText.т("to_close"), действие: закрыть)
            Spacer(minLength: 0)
            Text(заголовок)
                .font(.headline)
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Color.clear
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }
}

// MARK: - «Ваше фото»: проверка и согласие

/**
 Своё фото крупно, в углу — фото вещи; отметка «Человек в кадре» (Vision на телефоне — только подсказка); полоса фото
 вещи, если их несколько; согласие — кто обработает фото, 24 часа, не для обучения. Первый раз кнопка — «Согласен,
 примерить», потом — «Примерить». Ниже — «Переснять».
 */
struct ШагПроверкиПримерочной: View {
    @ObservedObject var модель: МодельПримерочной
    let закрыть: () -> Void
    /// Сведения info (кто обработает фото, сколько осталось) могут прийти, когда шаг уже на экране.
    @ObservedObject private var готовность = ГотовностьПримерочной.shared
    @State private var появилось = false
    @Environment(\.accessibilityReduceMotion) private var меньшеДвижения

    init(модель: МодельПримерочной, закрыть: @escaping () -> Void) {
        self.модель = модель
        self.закрыть = закрыть
    }

    private func т(_ ключ: String) -> String { ПримерочнаяText.т(ключ) }

    private var тихо: Bool { меньшеДвижения || ДвижениеСайта.тихо }

    var body: some View {
        VStack(spacing: 0) {
            ШапкаПримерочной(заголовок: модель.вид.заголовокПроверки, закрыть: закрыть)
            ScrollView {
                VStack(spacing: 16) {
                    снимок
                    отметка
                    if модель.товар.фотоАдреса.count > 1 {
                        полосаВещи
                    }
                    согласие
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 20)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            кнопки
        }
        .onAppear {
            guard !появилось else { return }
            if тихо {
                появилось = true
            } else {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.78).delay(0.05)) { появилось = true }
            }
        }
    }

    /// Своё фото и вещь в углу: вещь «прилетает» к фото пружиной.
    private var снимок: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let фото = модель.фотоЧеловека {
                    Image(uiImage: фото)
                        .resizable()
                        .scaledToFit()
                } else {
                    Color.white.opacity(0.06)
                        .aspectRatio(0.75, contentMode: .fit)
                }
            }
            .frame(maxHeight: 440)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            }
            .accessibilityLabel(модель.вид.заголовокПроверки)
            if let вещь = модель.фотоВещи {
                Image(uiImage: вещь)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 86, height: 86)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                            .strokeBorder(Color.white, lineWidth: 2.5)
                    }
                    .shadow(color: Color.black.opacity(0.45), radius: 10, x: 0, y: 4)
                    .rotationEffect(.degrees(появилось ? 4 : 16))
                    .offset(x: появилось ? 10 : 70, y: появилось ? 10 : 40)
                    .opacity(появилось ? 1 : 0)
                    .accessibilityLabel(модель.вид.подписьВещи)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Отметка Vision: у человека «Человек в кадре» — хорошо; у машины и комнаты люди в кадре — предупреждение.
    @ViewBuilder
    private var отметка: some View {
        if let люди = модель.человекВКадре {
            let итог = модель.вид.отметка(люди: люди)
            HStack(spacing: 8) {
                Image(systemName: итог.хорошо ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(итог.хорошо ? Theme.зелёныйЯркий : Theme.оранжевый)
                    .accessibilityHidden(true)
                Text(итог.текст)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }

    /// Какое фото вещи примерить — миниатюры объявления, выбранная — в зелёной рамке.
    private var полосаВещи: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(модель.вид.заголовокФотоВещи)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.white.opacity(0.86))
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(модель.товар.фотоАдреса.enumerated()), id: \.offset) { номер, адрес in
                        миниатюра(номер: номер, адрес: адрес)
                    }
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func миниатюра(номер: Int, адрес: URL) -> some View {
        let выбрана = номер == модель.номерФото
        return Button { модель.выбратьФотоВещи(номер) } label: {
            КартинкаЛенты(адрес, пунктов: 64) {
                Color.white.opacity(0.08)
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                    .strokeBorder(выбрана ? Theme.зелёныйЯркий : Color.white.opacity(0.18), lineWidth: выбрана ? 3 : 1)
            }
            .scaleEffect(выбрана ? 1 : 0.94)
            .animation(ДвижениеСайта.выбор, value: выбрана)
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.92))
        .accessibilityLabel(String(format: т("to_item_n"), номер + 1))
        .accessibilityAddTraits(выбрана ? .isSelected : [])
    }

    /// Кто обработает фото, сколько хранится, что не для обучения; осталось примерок — если сервер сказал.
    private var согласие: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.зелёныйЯркий)
                    .accessibilityHidden(true)
                Text(String(format: т("to_privacy"), модель.ктоОбработает))
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let осталось = модель.осталось {
                Text(String(format: т("to_left"), осталось))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.шапкаМята)
                    .padding(.leading, 28)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var кнопки: some View {
        VStack(spacing: 10) {
            ЗелёнаяКнопкаФото(заголовок: т(модель.согласиеДано ? "to_go" : "to_agree_go"), значок: "sparkles") {
                модель.примерить()
            }
            ЗелёнаяКнопкаФото(заголовок: т("to_retake"), значок: "camera.rotate", контурная: true, наТёмном: true) {
                модель.переснять()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.35)], startPoint: .top,
                           endPoint: .bottom)
                .ignoresSafeArea()
        }
    }
}

// MARK: - «Войдите», «Скоро», «Не получилось»

/// Значок в светящемся круге, заголовок, готовый текст и кнопки по случаю. Отказ своего ИИ — ещё «Свой ИИ» (окно
/// настроек); посреди опроса — «Проверить ещё раз» той же примерки.
struct ШагОтказаПримерочной: View {
    @ObservedObject var модель: МодельПримерочной
    let закрыть: () -> Void
    /// Товары App Store: пришли — «Больше примерок с Kliko AI» встаёт сама.
    @ObservedObject private var покупки = ПокупкиApple.shared
    @State private var появилось = false
    @Environment(\.accessibilityReduceMotion) private var меньшеДвижения

    init(модель: МодельПримерочной, закрыть: @escaping () -> Void) {
        self.модель = модель
        self.закрыть = закрыть
    }

    private func т(_ ключ: String) -> String { ПримерочнаяText.т(ключ) }

    private var значок: String {
        switch модель.шаг {
        case .вход: return "person.crop.circle.badge.checkmark"
        case .скоро: return "hourglass"
        default: return модель.отказ?.код == "limit" ? "clock.badge.exclamationmark" : "exclamationmark.triangle.fill"
        }
    }

    private var заголовок: String {
        switch модель.шаг {
        case .вход: return т("to_login_t")
        case .скоро: return т("to_soon_t")
        default: return т("to_err_t")
        }
    }

    private var текст: String {
        switch модель.шаг {
        case .вход: return т("to_login_s")
        case .скоро: return т("to_soon_s")
        default:
            let основа = модель.отказ?.текст ?? т("to_err_fail")
            /* Без чисел: сколько примерок с пакетом — предложение сервера, решает владелец. */
            return больше ? основа + "\n" + ЛимитText.т("lu_tryon_note") : основа
        }
    }

    /**
     Примерки на сегодня кончились, а пакет Kliko AI поднимет суточный лимит (владелец 16.10.2026: «в окне предлагать
     расширить сразу»): «Больше примерок с Kliko AI» — первой; после покупки — та же примерка тем же обработчиком.
     */
    private var больше: Bool {
        модель.отказ?.код == "limit" && модель.можноБольше && РасширениеЛимита.есть(РасширениеЛимита.примерка)
    }

    var body: some View {
        VStack(spacing: 0) {
            ШапкаПримерочной(заголовок: модель.вид.заголовок, закрыть: закрыть)
            ScrollView {
                VStack(spacing: 0) {
                    Image(systemName: значок)
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(модель.шаг == .отказ ? Theme.оранжевый : Theme.зелёныйЯркий)
                        .frame(width: 84, height: 84)
                        .background(Color.white.opacity(0.08), in: Circle())
                        .overlay { Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1) }
                        .scaleEffect(появилось ? 1 : 0.7)
                        .opacity(появилось ? 1 : 0)
                        .padding(.bottom, 18)
                        .accessibilityHidden(true)
                    Text(заголовок)
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(Color.white)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 8)
                        .accessibilityAddTraits(.isHeader)
                    Text(текст)
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 26)
                    кнопки
                }
                .padding(.horizontal, 32)
                .padding(.top, 70)
                .padding(.bottom, 32)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            if меньшеДвижения || ДвижениеСайта.тихо {
                появилось = true
            } else {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { появилось = true }
            }
        }
    }

    @ViewBuilder
    private var кнопки: some View {
        VStack(spacing: 10) {
            switch модель.шаг {
            case .вход:
                ЗелёнаяКнопкаФото(заголовок: т("to_login"), значок: "person.fill") {
                    ВходПоверх.показать(готово: { модель.послеВхода() })
                }
            case .скоро:
                ЗелёнаяКнопкаФото(заголовок: т("to_ok"), значок: "checkmark", действие: закрыть)
            default:
                кнопкиОтказа
            }
            if модель.шаг != .скоро {
                ЗелёнаяКнопкаФото(заголовок: т("to_close"), значок: "xmark", контурная: true, наТёмном: true,
                                  действие: закрыть)
            }
        }
    }

    @ViewBuilder
    private var кнопкиОтказа: some View {
        if больше {
            КнопкаРасширения(цепочка: РасширениеЛимита.примерка, действие: { вид in
                ЛистУслугиApple.показать(вид, готово: { модель.послеРасширения() })
            }) { занято, нажать in
                ЗелёнаяКнопкаФото(заголовок: ЛимитText.т("lu_more_tryon"), значок: "sparkles", действие: нажать)
                    .opacity(занято ? 0.6 : 1)
            }
        }
        if модель.продолжаемая {
            ЗелёнаяКнопкаФото(заголовок: т(модель.отказ?.код == "slow" ? "to_check_again" : "to_retry"),
                              значок: "arrow.clockwise") {
                модель.продолжить()
            }
        } else if модель.отказ?.повторить ?? true, модель.фотоЧеловека != nil {
            ЗелёнаяКнопкаФото(заголовок: т("to_retry"), значок: "arrow.clockwise") {
                модель.примерить()
            }
        }
        if let свой = модель.отказ?.свойИИ {
            ЗелёнаяКнопкаФото(заголовок: т("to_own_ai"), значок: "cpu", контурная: true, наТёмном: true) {
                ОкноСвоегоИИ.показатьОтказ(свой)
            }
        }
        if модель.отказ?.переснять == true || (модель.отказ?.код != "not_clothes" && модель.отказ?.код != "limit") {
            ЗелёнаяКнопкаФото(заголовок: т("to_retake"), значок: "camera.rotate", контурная: true, наТёмном: true) {
                модель.переснять()
            }
        }
    }
}
