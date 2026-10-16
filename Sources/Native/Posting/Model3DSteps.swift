import SwiftUI
import UIKit

/**
 3D-ОБЗОР В ПОДАЧЕ — ШАГИ ОКНА ПОСЛЕ СЪЁМКИ: обзор ракурсов (поворот, пересъёмка, «Собрать 3D», согласие), сборка
 (кольцо и проценты) и готовая модель (превью поворотом, постер, «Посмотреть в 3D», честная пометка ИИ).

 Лимит сборок — своей фразой, без цен и ссылок на оплату; если пакет Kliko AI не действует и товар App Store загружен —
 под ней «Больше сборок с Kliko AI» (окно покупки Apple, правило 3.1.1). Подпись у модели всегда честная: «3D-модель
 создана ИИ по фото — детали могут отличаться».
 */

// MARK: - Обзор ракурсов

struct ШагОбзораРакурсов3D: View {
    @ObservedObject var модель: МодельСъёмкиОбзора3D
    let закрыть: () -> Void
    @ObservedObject private var хранилище = ХранилищеОбзора3DПодачи.shared
    @ObservedObject private var готовность = ГотовностьОбзора3DПодачи.shared
    @ObservedObject private var режим = РежимУстройства.shared
    /// Товары App Store: пришли — «Больше сборок с Kliko AI» встаёт сама.
    @ObservedObject private var покупки = ПокупкиApple.shared
    @Environment(\.accessibilityReduceMotion) private var меньшеДвижения
    /// Пакет Kliko AI уже действует (CAB_AI страницы кабинета) — лимит сборок с ним уже поднят; nil — не знаем.
    @State private var пакетДействует: Bool? = nil

    init(модель: МодельСъёмкиОбзора3D, закрыть: @escaping () -> Void) {
        self.модель = модель
        self.закрыть = закрыть
    }

    private func т(_ ключ: String) -> String { Обзор3DПодачиText.т(ключ) }

    private var тихо: Bool { меньшеДвижения || ДвижениеСайта.тихо }

    private var запись: ЗаписьОбзора3DПодачи? { модель.запись }

    /// Сервер собирает модели (build) — карточка сборки есть; лимит — внутри неё своей фразой.
    private var сборкаЕсть: Bool { готовность.сведения?.сборка == true && !готовность.нетСервера }

    /// Кнопка «Собрать 3D» сейчас.
    private var можноСобрать: Bool {
        guard сборкаЕсть, готовность.сборкаВозможна, let з = запись, з.всеСняты, !модель.согласие else { return false }
        if з.неУдалась {
            return ОтказОбзора3DПодачи(код: з.отказКод, текст: з.отказТекст).повторить
        }
        return true
    }

    var body: some View {
        VStack(spacing: 0) {
            ШапкаПримерочной(заголовок: т("m3_title"), закрыть: закрыть)
            ScrollView {
                VStack(spacing: 16) {
                    ПоворотРакурсовОбзора3D(кадры: модель.кадры, запись: запись, тихо: тихо, лёгкий: режим.лёгкий)
                        .frame(height: 300)
                    ПолоскаРакурсовОбзора3D(кадры: модель.кадры, запись: запись, текущий: nil,
                                            плохой: хранилище.отказЗагрузки[модель.ключ]?.ракурс, малая: false,
                                            нажать: { р in модель.снятьЗаново(р) })
                    Text(т("m3_tap_retake_hint"))
                        .font(.footnote)
                        .foregroundStyle(Color.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    состояниеЗагрузки
                    if сборкаЕсть { карточкаСборки }
                    if модель.согласие { карточкаСогласия }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            кнопки
        }
        .confirmationDialog(т("m3_remove_q"), isPresented: $модель.вопросУбрать, titleVisibility: .visible) {
            Button(т("m3_remove_yes"), role: .destructive) {
                модель.убрать()
                закрыть()
            }
            Button(т("m3_cancel"), role: .cancel) {}
        } message: {
            Text(т("m3_remove_s"))
        }
    }

    // MARK: Загрузка ракурсов и привязка

    @ViewBuilder
    private var состояниеЗагрузки: some View {
        if let отказ = хранилище.отказЗагрузки[модель.ключ] {
            СтрокаОбзора3D(значок: "exclamationmark.triangle.fill", цвет: Theme.оранжевый,
                           текст: отказ.ракурс >= 0
                               ? String(format: т("m3_angle_bad"), отказ.ракурс + 1, отказ.отказ.текст)
                               : отказ.отказ.текст)
        } else if let з = запись, хранилище.загружаем.contains(модель.ключ) {
            HStack(spacing: 10) {
                SiteSpinner(размер: 16, толщина: 2, дорожка: Color.white.opacity(0.15), верх: Theme.зелёныйЯркий)
                    .accessibilityHidden(true)
                Text(String(format: т("m3_uploading"), з.загружено, РакурсОбзора3DПодачи.всего))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        } else if let з = запись, з.всеЗагружены {
            if модель.правка && !з.привязано.isEmpty {
                СтрокаОбзора3D(значок: "checkmark.seal.fill", цвет: Theme.зелёныйЯркий, текст: т("m3_saved_listing"))
            } else {
                СтрокаОбзора3D(значок: "checkmark.circle.fill", цвет: Theme.зелёныйЯркий,
                               текст: т(модель.правка ? "m3_uploaded_edit" : "m3_uploaded"))
            }
        } else if запись?.всеСняты == true {
            VStack(alignment: .leading, spacing: 8) {
                СтрокаОбзора3D(значок: "icloud.slash", цвет: Theme.оранжевый, текст: т("m3_upload_wait"))
                Button(т("m3_retry")) { хранилище.возобновить(модель.подача) }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.зелёныйЯркий)
            }
        }
    }

    // MARK: Сборка ИИ

    private var карточкаСборки: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .frame(width: 36, height: 36)
                    .background(Theme.зелёныйЯркий, in: Circle())
                    .accessibilityHidden(true)
                Text(т("m3_build_t"))
                    .font(.headline)
                    .foregroundStyle(Color.white)
                    .accessibilityAddTraits(.isHeader)
            }
            Text(т(модель.вид == .машина ? "m3_build_s_car" : "m3_build_s"))
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            if let з = запись, з.неУдалась, !з.отказТекст.isEmpty {
                СтрокаОбзора3D(значок: "exclamationmark.triangle.fill", цвет: Theme.оранжевый, текст: з.отказТекст)
            }
            if let осталось = готовность.сведения?.осталось {
                Text(осталось > 0 ? String(format: т("m3_left"), осталось) : т("m3_limit"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(осталось > 0 ? Theme.шапкаМята : Theme.оранжевый)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if большеСборок { кнопкаБольшеСборок }
            ПометкаИИОбзора3D()
        }
        .task(id: упёрлисьВЛимит) {
            guard упёрлисьВЛимит, Config.цифровыеПокупки else { return }
            let с = try? await КабинетСайта.состояние(ждать: false)
            /* CAB_AI не пришёл — неизвестно, действует ли пакет: nil, кнопки нет (второй пакет лимит не поднимет). */
            let квота: КабинетСайта.КвотаИИ? = с?.ии
            пакетДействует = квота.map { $0.оплачено }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                .strokeBorder(Theme.зелёныйЯркий.opacity(0.3), lineWidth: 1)
        }
    }

    /// Сборки на сегодня кончились: left 0 в info или start ответил limit.
    private var упёрлисьВЛимит: Bool {
        готовность.сведения?.осталось == 0 || запись?.отказКод == "limit"
    }

    /**
     Пакет Kliko AI (или PRO с днями ИИ) поднимает суточный лимит сборок (docs/SERVER_3D.md, §10) — владелец 16.10.2026:
     «в окне предлагать расширить сразу». Пакет уже действует — не продаётся, остаётся честная фраза.
     */
    private var большеСборок: Bool {
        упёрлисьВЛимит && пакетДействует == false && РасширениеЛимита.есть(РасширениеЛимита.сборка3D)
    }

    /// «Больше сборок с Kliko AI»: окно покупки App Store; после «Готово» — сведения заново и сборка тех же ракурсов
    /// (первый раз она сама спросит согласие).
    private var кнопкаБольшеСборок: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ЛимитText.т("lu_3d_note"))
                .font(.footnote)
                .foregroundStyle(Color.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
            КнопкаРасширения(цепочка: РасширениеЛимита.сборка3D, действие: { вид in
                ЛистУслугиApple.показать(вид, готово: {
                    Task { @MainActor in
                        ГотовностьОбзора3DПодачи.shared.устарели()
                        await ГотовностьОбзора3DПодачи.shared.проверить()
                        пакетДействует = nil
                        модель.собрать()
                    }
                })
            }) { занято, нажать in
                ЗелёнаяКнопкаФото(заголовок: ЛимитText.т("lu_more_3d"), значок: "sparkles", действие: нажать)
                    .opacity(занято ? 0.6 : 1)
            }
        }
    }

    /// Согласие перед первой сборкой (App Review 5.1.2(i)): кто обработает ракурсы, сколько хранятся, не для обучения.
    private var карточкаСогласия: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(т("m3_consent_t"))
                .font(.headline)
                .foregroundStyle(Color.white)
                .accessibilityAddTraits(.isHeader)
            Text(String(format: т("m3_consent"), модель.ктоСоберёт))
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            ЗелёнаяКнопкаФото(заголовок: т("m3_consent_yes"), значок: "checkmark") { модель.согласен() }
            Button(т("m3_not_now")) {
                withAnimation(ДвижениеСайта.уход) { модель.согласие = false }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.white.opacity(0.75))
            .frame(maxWidth: .infinity)
        }
        .padding(14)
        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
        }
        .transition(.opacity)
    }

    // MARK: Кнопки

    private var кнопки: some View {
        VStack(spacing: 10) {
            if можноСобрать {
                ЗелёнаяКнопкаФото(заголовок: т(запись?.неУдалась == true ? "m3_build_again" : "m3_build"),
                                  значок: "cube.transparent") {
                    модель.собрать()
                }
            }
            if модель.правка && запись?.привязано.isEmpty != false {
                if хранилище.привязываем(модель.подача) {
                    HStack(spacing: 10) {
                        SiteSpinner(размер: 18, толщина: 2.2, дорожка: Color.white.opacity(0.15),
                                    верх: Theme.зелёныйЯркий)
                        Text(т("m3_saving"))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.white)
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .accessibilityElement(children: .combine)
                } else {
                    ЗелёнаяКнопкаФото(заголовок: т("m3_save_listing"), значок: "square.and.arrow.down",
                                      контурная: можноСобрать, наТёмном: true) {
                        модель.сохранитьВОбъявление()
                    }
                    .disabled(запись?.всеСняты != true)
                }
            } else {
                ЗелёнаяКнопкаФото(заголовок: т("m3_done"), значок: "checkmark", контурная: можноСобрать,
                                  наТёмном: true) {
                    закрыть()
                }
            }
            Button(т("m3_remove")) { модель.вопросУбрать = true }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.малиновый)
                .padding(.top, 2)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Сборка

/**
 «Собираем 3D»: кольцо ракурсов, крупные проценты (цифры перекатываются, между опросами сами чуть подрастают, не выше 92
 до готовности), подпись этапа, полоса. Окно можно закрыть — сборка продолжится, карточка в шаге «Фото» покажет ход.
 */
struct ШагСборкиОбзора3D: View {
    @ObservedObject var модель: МодельСъёмкиОбзора3D
    let закрыть: () -> Void
    @ObservedObject private var хранилище = ХранилищеОбзора3DПодачи.shared
    @ObservedObject private var режим = РежимУстройства.shared
    @Environment(\.accessibilityReduceMotion) private var меньшеДвижения
    @State private var показ = 0

    init(модель: МодельСъёмкиОбзора3D, закрыть: @escaping () -> Void) {
        self.модель = модель
        self.закрыть = закрыть
    }

    private func т(_ ключ: String) -> String { Обзор3DПодачиText.т(ключ) }

    private var тихо: Bool { меньшеДвижения || ДвижениеСайта.тихо }

    private var запись: ЗаписьОбзора3DПодачи? { модель.запись }

    private var заминка: String? { хранилище.заминка[модель.ключ] }

    var body: some View {
        VStack(spacing: 0) {
            ШапкаПримерочной(заголовок: т("m3_title"), закрыть: закрыть)
            Spacer(minLength: 12)
            КольцоСборкиОбзора3D(кадры: модель.кадры, запись: запись, тихо: тихо || режим.лёгкий)
                .frame(maxWidth: 420)
                .frame(height: 280)
            ход
            ПолосаПримерочной(доля: CGFloat(показ) / 100, тихо: тихо)
                .frame(maxWidth: 320)
                .padding(.top, 14)
                .padding(.horizontal, 40)
                .accessibilityHidden(true)
            Text(заминка ?? т("m3_building_sub"))
                .font(.footnote)
                .foregroundStyle(заминка == nil ? Color.white.opacity(0.6) : Theme.оранжевый)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
                .padding(.horizontal, 36)
            Spacer(minLength: 16)
            кнопки
        }
        .frame(maxWidth: .infinity)
        .onAppear { показ = max(показ, запись?.прогресс ?? 0) }
        .task { await подтягивать() }
    }

    private var ход: some View {
        VStack(spacing: 2) {
            Text(т("m3_building"))
                .font(.title3.weight(.heavy))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(String(показ) + "%")
                .font(.system(size: 48, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(LinearGradient(colors: [Color.white, Theme.шапкаМята], startPoint: .top,
                                                endPoint: .bottom))
                .contentTransition(.numericText())
                .animation(ДвижениеСайта.прогресс, value: показ)
                .accessibilityLabel(String(format: т("m3_progress_a11y"), показ))
            Text(т(ключЭтапа))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.зелёныйЯркий)
                .id(ключЭтапа)
                .transition(.opacity)
                .animation(ДвижениеСайта.смена, value: ключЭтапа)
        }
        .padding(.top, 14)
        .padding(.horizontal, 24)
    }

    /// Этап: сервер назвал (stage) — его подпись; нет — по процентам.
    private var ключЭтапа: String {
        if хранилище.запускаем.contains(модель.ключ) || запись?.задача.isEmpty != false { return "m3_stage_upload" }
        switch запись?.этап ?? "" {
        case "queue": return "m3_stage_queue"
        case "mesh": return "m3_stage_mesh"
        case "texture": return "m3_stage_texture"
        case "convert", "usdz": return "m3_stage_convert"
        default: break
        }
        if запись?.состояние == "queued" && показ < 5 { return "m3_stage_queue" }
        switch показ {
        case ..<30: return "m3_stage_check"
        case ..<60: return "m3_stage_mesh"
        case ..<88: return "m3_stage_texture"
        default: return "m3_stage_convert"
        }
    }

    /// Проценты сервера не убывают; между опросами — по одному раз в 1,5 с, не дальше сервера на 8 и не выше 92.
    private func подтягивать() async {
        while !Task.isCancelled {
            let сервер = запись?.прогресс ?? 0
            if сервер > показ {
                показ = сервер
            } else if заминка == nil && запись?.задача.isEmpty == false && показ < min(92, сервер + 8) {
                показ += 1
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }
    }

    private var кнопки: some View {
        VStack(spacing: 10) {
            if заминка != nil {
                ЗелёнаяКнопкаФото(заголовок: т("m3_check_again"), значок: "arrow.clockwise") { модель.продолжить() }
            }
            ЗелёнаяКнопкаФото(заголовок: т("m3_hide"), значок: "chevron.down", контурная: заминка != nil,
                              наТёмном: true) {
                закрыть()
            }
            Button(т("m3_cancel_build")) {
                ОткликСайта.выбор()
                модель.отменитьСборку()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.white.opacity(0.75))
            .padding(.top, 2)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Готово

/// Модель собрана: превью поворотом (ракурсы) и постер модели, честная пометка, «Посмотреть в 3D» (AR Quick Look),
/// «Готово» или «Сохранить в объявление», «Переснять ракурсы».
struct ШагГотовоОбзора3D: View {
    @ObservedObject var модель: МодельСъёмкиОбзора3D
    let закрыть: () -> Void
    @ObservedObject private var хранилище = ХранилищеОбзора3DПодачи.shared
    @ObservedObject private var режим = РежимУстройства.shared
    @Environment(\.accessibilityReduceMotion) private var меньшеДвижения
    @State private var появилось = false

    init(модель: МодельСъёмкиОбзора3D, закрыть: @escaping () -> Void) {
        self.модель = модель
        self.закрыть = закрыть
    }

    private func т(_ ключ: String) -> String { Обзор3DПодачиText.т(ключ) }

    private var тихо: Bool { меньшеДвижения || ДвижениеСайта.тихо }

    private var запись: ЗаписьОбзора3DПодачи? { модель.запись }

    var body: some View {
        VStack(spacing: 0) {
            ШапкаПримерочной(заголовок: т("m3_title"), закрыть: закрыть)
            ScrollView {
                VStack(spacing: 14) {
                    витрина
                    Text(т("m3_done_t"))
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(Color.white)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text(т(модель.вид == .машина ? "m3_done_s_car" : "m3_done_s"))
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    ПометкаИИОбзора3D()
                    if модель.правка, let з = запись, !з.привязано.isEmpty {
                        СтрокаОбзора3D(значок: "checkmark.seal.fill", цвет: Theme.зелёныйЯркий,
                                       текст: т("m3_saved_listing"))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            кнопки
        }
        .onAppear {
            if тихо {
                появилось = true
            } else {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) { появилось = true }
            }
        }
    }

    /// Превью поворотом: ракурсы листаются пальцем (и сами, если можно); знак «3D · ИИ» в углу, постер модели с сервера —
    /// плиткой справа сверху (нажатие — AR Quick Look).
    private var витрина: some View {
        ZStack(alignment: .topLeading) {
            ПоворотРакурсовОбзора3D(кадры: модель.кадры, запись: запись, тихо: тихо, лёгкий: режим.лёгкий)
                .frame(maxWidth: .infinity)
                .frame(height: 300)
                .background(Color.white.opacity(0.05),
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
                .scaleEffect(появилось ? 1 : 0.92)
                .opacity(появилось ? 1 : 0)
            Label(т("m3_badge"), systemImage: "cube.transparent")
                .font(.caption.weight(.heavy))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Theme.зелёныйЯркий, in: Capsule())
                .padding(10)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .topTrailing) {
            if let постер = модель.постер {
                Button { модель.открыть3D() } label: {
                    Image(uiImage: постер)
                        .resizable()
                        .scaledToFit()
                        .padding(4)
                        .frame(width: 92, height: 92)
                        .background(Color.white.opacity(0.1),
                                    in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                                .strokeBorder(Theme.зелёныйЯркий.opacity(0.6), lineWidth: 1.5)
                        }
                }
                .buttonStyle(НажатиеКнопкиФото(сжатие: 0.94))
                .disabled(запись?.адресUSDZ == nil || модель.открываем)
                .padding(10)
                .accessibilityLabel(т("m3_poster_a11y"))
                .accessibilityHint(т("m3_view3d"))
            }
        }
    }

    private var кнопки: some View {
        VStack(spacing: 10) {
            if запись?.адресUSDZ != nil {
                if модель.открываем {
                    HStack(spacing: 10) {
                        SiteSpinner(размер: 18, толщина: 2.2, дорожка: Color.white.opacity(0.15),
                                    верх: Theme.зелёныйЯркий)
                        Text(т("m3_opening"))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.white)
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .accessibilityElement(children: .combine)
                } else {
                    ЗелёнаяКнопкаФото(заголовок: т("m3_view3d"), значок: "arkit") { модель.открыть3D() }
                }
            }
            if модель.правка && запись?.привязано.isEmpty != false {
                ЗелёнаяКнопкаФото(заголовок: т(хранилище.привязываем(модель.подача) ? "m3_saving" : "m3_save_listing"),
                                  значок: "square.and.arrow.down", контурная: true, наТёмном: true) {
                    модель.сохранитьВОбъявление()
                }
                .disabled(хранилище.привязываем(модель.подача))
            } else {
                ЗелёнаяКнопкаФото(заголовок: т("m3_done"), значок: "checkmark", контурная: true, наТёмном: true) {
                    закрыть()
                }
            }
            Button(т("m3_reshoot")) {
                ОткликСайта.выбор()
                модель.сброситьМодель()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.white.opacity(0.75))
            .padding(.top, 2)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Мелкие части

/// Строка-отметка: значок цвета и текст на тёмной плашке.
struct СтрокаОбзора3D: View {
    let значок: String
    let цвет: Color
    let текст: String

    init(значок: String, цвет: Color, текст: String) {
        self.значок = значок
        self.цвет = цвет
        self.текст = текст
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: значок)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(цвет)
                .accessibilityHidden(true)
            Text(текст)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Честная пометка: «3D-модель создана ИИ по фото — детали могут отличаться».
struct ПометкаИИОбзора3D: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.шапкаМята)
                .accessibilityHidden(true)
            Text(Обзор3DПодачиText.т("m3_ai_note"))
                .font(.footnote)
                .foregroundStyle(Color.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
