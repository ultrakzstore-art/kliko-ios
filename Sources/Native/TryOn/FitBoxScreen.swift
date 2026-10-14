import SwiftUI
import UIKit
import ARKit
import Combine

/**
 «ПОМЕСТИТСЯ ЛИ?» — ОКНО И ЭКРАН (владелец 13.10.2026: «распиши примерочную; нужен ли 3D — очки, шины, диски?» →
 «нужнее охват всего»).

 Вход один — хаб «Примерить / проверить» (TryOnHub.swift): у мебели и крупной техники он ставит кнопку «Поместится ли?»
 и по нажатию зовёт ОкноГабаритов.открыть(товар:). Есть ли AR на устройстве — ОкноГабаритов.доступно (нет — кнопки быть
 не должно; если её всё же нажали — окно честно скажет, что AR нет, и покажет размеры для рулетки).

 Экран — во весь экран и всегда тёмный (камера — не лист: смахивание листа спорило бы с пальцем, которым двигают
 коробку). Сверху — ✕, «Поместится ли?» с названием объявления и размеры коробки (нажатие — изменить). Под ними —
 подсказка по шагу: «Медленно ведите телефоном по полу» → «Коснитесь пола…» → «Два пальца — поворот, палец — сдвиг»
 (и что мешает: быстро, мало деталей, пауза). Внизу — «Прижать к стене» (если ARKit нашёл стену), «Убрать», затвор
 «Снимок» и «Размеры»; под ними — «Размеры — со слов продавца».

 Размеров нет или они сомнительны (РазборГабаритов, FitBoxSize.swift) — сначала лист «Укажите размеры» (найденное —
 уже в полях); закрыли его без размеров — окно переходит в линейку (ей размеры вещи не нужны), без линейки — закрывается. Камера запрещена — заглушка с «Открыть Настройки»; AR не
 запустился — «Повторить». VoiceOver: сцена — один элемент с состоянием и действиями «Поставить в центр», «Повернуть
 влево/вправо»; касания проходят в сцену напрямую.

 Линейка (владелец 14.10.2026): под заголовком — переключатель «Коробка / Линейка» (Config.габаритыЛинейка). В линейке
 посреди экрана — прицел, сверху — её подсказка, внизу — её панель: «Сравнить с вещью», «Очистить», «Отменить», «+»,
 «Снимок» и точность (части — FitBoxRulerViews.swift, модель — FitBoxRuler.swift). VoiceOver в линейке: «Поставить
 точку», «Отменить последнее», «Убрать все отрезки». Линейке размеры вещи не нужны — без них она работает (сравнения
 нет). Замер вещи из подачи (ОкноГабаритов.открытьЗамер, «Измерить в AR» в блоке «Габариты, см»): то же окно, только
 линейка — «Измерить вещь», без переключателя, справа «Готово»: три отрезка — ширина, высота, глубина — уходят в поля.

 Вещь (владелец 14.10.2026: «3D-обзор надо сделать за счёт ИИ»): переключатель — «Вещь / Коробка / Линейка», «Вещь» —
 первой и по умолчанию, если у объявления есть фото или 3D-модель (ВещьГабаритов, FitBoxItem.swift). Низ — как у коробки
 (сцена та же), над затвором — плашка вещи (ПлашкаВещиГабаритов, FitBoxItemViews.swift): «3D-модель ИИ», «Фото вещи в
 реальном размере» или «Загружаем…», и честная пометка. Строки сцены в «Вещи» говорят «вещь», а не «коробка».
 */
@MainActor
enum ОкноГабаритов {
    private static var последнееОткрытие: Date? = nil

    /// Есть ли на устройстве AR с поиском плоскостей (ARWorldTrackingConfiguration). false — кнопки «Поместится ли?»
    /// быть не должно (хаб, ПодборПримерки).
    static var доступно: Bool { поддержка }

    private static let поддержка: Bool = {
        #if targetEnvironment(simulator)
        return false
        #else
        return ARWorldTrackingConfiguration.isSupported
        #endif
    }()

    /// Открыть «Поместится ли?» поверх того, что на экране (во весь экран). Защита от двойного нажатия: второе окно за
    /// секунду не кладём поверх первого.
    static func открыть(товар: Listing) {
        guard Config.габаритыAR else { return }
        let найдено = РазборГабаритов.найти(товар)
        показать { закрыть in AnyView(ЭкранГабаритов(товар: товар, найдено: найдено, закрыть: закрыть)) }
    }

    /// «Измерить в AR» из подачи (блок «Габариты, см», ЛинейкаПодачи, PostingDims.swift): то же окно сразу линейкой —
    /// без коробки и сравнения; «Готово» отдаёт первые три отрезка как ширину, высоту и глубину, см (не мерили — nil).
    static func открытьЗамер(название: String, готово: @escaping (Double?, Double?, Double?) -> Void) {
        guard Config.габаритыAR, Config.габаритыЛинейка, доступно else { return }
        показать { закрыть in AnyView(ЭкранГабаритов(замер: название, готово: готово, закрыть: закрыть)) }
    }

    /// Окно во весь экран поверх верхнего контроллера; экран получает «закрыть».
    private static func показать(_ экран: @escaping (@escaping () -> Void) -> AnyView) {
        let сейчас = Date()
        if let прежнее = последнееОткрытие, сейчас.timeIntervalSince(прежнее) < 1 { return }
        последнееОткрытие = сейчас
        Task { @MainActor in
            for попытка in 0..<12 {
                if let верх = ОкноГабаритов.верхний() {
                    let хост = UIHostingController<AnyView>(rootView: AnyView(EmptyView()))
                    let закрыть: () -> Void = { [weak хост] in
                        хост?.dismiss(animated: true)
                    }
                    хост.rootView = экран(закрыть)
                    хост.modalPresentationStyle = .fullScreen
                    хост.overrideUserInterfaceStyle = .dark
                    хост.view.backgroundColor = .black
                    верх.present(хост, animated: true)
                    return
                }
                try? await Task.sleep(nanoseconds: попытка == 0 ? 120_000_000 : 250_000_000)
            }
        }
    }

    /// Верхний показанный контроллер ключевого окна; nil — что-то ещё уезжает или приезжает (как у ПоверхВсего —
    /// своя копия, чтобы окно не зависело от правок кабинета).
    private static func верхний() -> UIViewController? {
        let окна = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        guard let окно = окна.first(where: { $0.isKeyWindow }) ?? окна.first,
              var верх = окно.rootViewController else { return nil }
        while let следующий = верх.presentedViewController {
            if следующий.isBeingDismissed || следующий.isBeingPresented { return nil }
            верх = следующий
        }
        if верх.isBeingDismissed { return nil }
        return верх
    }
}

extension ГабаритыВещи {
    /// Для VoiceOver: «Ширина 60, Высота 85, Глубина 55».
    var озвучка: String {
        [
            ГабаритыText.т("fb_w") + " " + Self.число(ширина),
            ГабаритыText.т("fb_h") + " " + Self.число(высота),
            ГабаритыText.т("fb_d") + " " + Self.число(глубина)
        ].joined(separator: ", ")
    }
}

// MARK: - Экран

struct ЭкранГабаритов: View {
    @StateObject private var модель: МодельГабаритов
    let закрыть: () -> Void
    /// Замер вещи для подачи: «Готово» — ширина, высота, глубина (см) первых трёх отрезков.
    private let готовоЗамера: ((Double?, Double?, Double?) -> Void)?
    @Environment(\.accessibilityReduceMotion) private var меньшеДвижения
    @ScaledMetric(relativeTo: .title) private var затвор: CGFloat = 70

    init(товар: Listing, найдено: НайденныеГабариты, закрыть: @escaping () -> Void) {
        _модель = StateObject(wrappedValue: МодельГабаритов(товар: товар, найдено: найдено))
        self.закрыть = закрыть
        готовоЗамера = nil
    }

    /// «Измерить в AR» из подачи: только линейка; название — объявления, которое подают (может быть пустым).
    init(замер название: String, готово: @escaping (Double?, Double?, Double?) -> Void, закрыть: @escaping () -> Void) {
        let товар = Listing(id: "measure", title: название, price: nil, oldPrice: nil, negotiable: false,
                            forRent: false, rentPriceDay: nil, thumb: nil, city: "", isTop: false, isNew: false)
        _модель = StateObject(wrappedValue: МодельГабаритов(товар: товар, найдено: НайденныеГабариты(),
                                                             замерВещи: true))
        self.закрыть = закрыть
        готовоЗамера = готово
    }

    /// Строки коробки; в режиме «Вещь» — «вещь» вместо «коробки» (ВещьГабаритовText.вместоКоробки).
    private func т(_ ключ: String) -> String {
        модель.режим == .вещь ? ВещьГабаритовText.вместоКоробки(ключ) : ГабаритыText.т(ключ)
    }

    private var тихо: Bool { меньшеДвижения || ДвижениеСайта.тихо }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            if ОкноГабаритов.доступно {
                фон
                if модель.режим == .линейка && модель.камера == .идёт {
                    ПрицелЛинейкиГабаритов(живое: модель.линейка.живое)
                        .ignoresSafeArea()
                }
                VStack(spacing: 0) {
                    верх
                    переключатель
                    подсказки
                    Spacer(minLength: 12)
                    низ
                }
            } else {
                VStack(spacing: 0) {
                    верх
                    безAR
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .sheet(isPresented: $модель.листРазмеров, onDismiss: листЗакрыт) {
            ЛистРазмеровГабаритов(найдено: модель.найдено, текущие: модель.габариты) { новые in
                модель.задать(новые)
                модель.листРазмеров = false
            } отмена: {
                модель.листРазмеров = false
            }
        }
        .sheet(item: $модель.снимок) { снимок in
            ЛистСнимкаГабаритов(снимок: снимок, габариты: модель.габариты) {
                модель.снимок = nil
            }
        }
        .onAppear { модель.появился() }
        .onDisappear { модель.ушёл() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            модель.вФон()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            модель.изФона()
        }
    }

    /// Лист размеров закрыли, а размеров так и нет — коробку ставить не с чего: окно остаётся линейкой (ей размеры вещи не
    /// нужны — померить нишу); линейки нет — закрываем и окно.
    private func листЗакрыт() {
        if модель.габариты == nil && !модель.безРазмеров() { закрытьОкно() }
    }

    /// Закрыть окно насовсем: модель после ухода с экрана разберёт ARView (а не только поставит сессию на паузу).
    private func закрытьОкно() {
        модель.закрываем()
        закрыть()
    }

    /// «Готово» замера вещи: первые три отрезка — в поля подачи, окно закрывается.
    private func завершитьЗамер() {
        let замеры = модель.линейка.замеры
        готовоЗамера?(замеры.ширина, замеры.высота, замеры.глубина)
        закрытьОкно()
    }

    // MARK: Сцена или заглушка

    @ViewBuilder
    private var фон: some View {
        switch модель.камера {
        case .запрещена:
            заглушка(значок: "camera.fill", заголовок: т("fb_denied"), текст: т("fb_denied_hint"),
                     кнопка: т("fb_settings"), действие: открытьНастройки)
        case .сбой:
            заглушка(значок: "exclamationmark.triangle", заголовок: т("fb_failed"), текст: т("fb_failed_hint"),
                     кнопка: т("fb_retry")) {
                модель.повторить()
            }
        case .ждём, .идёт, .пауза:
            сцена
        }
    }

    private var сцена: some View {
        СценаГабаритовAR(модель: модель)
            .ignoresSafeArea()
            .accessibilityElement(children: .ignore)
            .modifier(ОзвучкаСценыЛинейкиГабаритов(линейка: модель.линейка, включена: модель.режим == .линейка,
                                                   подписьКоробки: т("fb_scene_a11y"),
                                                   значениеКоробки: модель.описаниеСостояния))
            .accessibilityAddTraits(.allowsDirectInteraction)
            .accessibilityActions { действияСцены }
    }

    /// Действия VoiceOver у сцены — по режиму.
    @ViewBuilder
    private var действияСцены: some View {
        if модель.режим == .линейка {
            Button(ЛинейкаГабаритовText.т("fr_add")) { модель.линейка.добавить() }
            Button(ЛинейкаГабаритовText.т("fr_undo_a11y")) { модель.линейка.отменить() }
            Button(ЛинейкаГабаритовText.т("fr_clear_a11y")) { модель.линейка.очистить() }
        } else {
            Button(т("fb_place_center")) { модель.поставитьВЦентр() }
            Button(т("fb_rot_left")) { модель.повернуть(влево: true) }
            Button(т("fb_rot_right")) { модель.повернуть(влево: false) }
        }
    }

    private func заглушка(значок: String, заголовок: String, текст: String, кнопка: String,
                          действие: @escaping () -> Void) -> some View {
        VStack(spacing: 14) {
            Image(systemName: значок)
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(Theme.шапкаМята)
                .accessibilityHidden(true)
            Text(заголовок)
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(текст)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .opacity(0.8)
            Button(action: действие) {
                Text(кнопка)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 22)
                    .frame(minHeight: 46)
                    .background(Theme.зелёныйЯркий, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(НажатиеКнопкиФото(сжатие: 0.96))
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 32)
        .frame(maxWidth: 460)
    }

    private func открытьНастройки() {
        guard let адрес = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(адрес)
    }

    // MARK: Верх

    private var верх: some View {
        HStack(alignment: .center, spacing: 10) {
            КруглаяКнопкаФото(значок: "xmark", подпись: т("fb_close")) { закрытьОкно() }
            VStack(alignment: .leading, spacing: 1) {
                Text(модель.замерВещи ? ЛинейкаГабаритовText.т("fr_meas_title") : т("fb_title"))
                    .font(.headline.weight(.heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if !модель.товар.title.isEmpty {
                    Text(модель.товар.title)
                        .font(.caption)
                        .lineLimit(1)
                        .opacity(0.75)
                }
            }
            .foregroundStyle(Color.white)
            .shadow(color: Color.black.opacity(0.5), radius: 4)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 4)
            if модель.замерВещи {
                КнопкаГотовоЗамераЛинейки(линейка: модель.линейка) { завершитьЗамер() }
            } else if let габариты = модель.габариты {
                кнопкаРазмеров(габариты)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func кнопкаРазмеров(_ габариты: ГабаритыВещи) -> some View {
        Button {
            ОткликСайта.выбор()
            модель.листРазмеров = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "ruler")
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
                Text(габариты.строка + " " + т("fb_cm"))
                    .font(.footnote.weight(.bold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(Color.black.opacity(0.45), in: Capsule())
            .overlay { Capsule().strokeBorder(Theme.шапкаМята.opacity(0.5), lineWidth: 1) }
            .contentShape(Capsule())
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.95))
        .accessibilityLabel(ГабаритыText.т("fb_sizes_a11y", габариты.озвучка))
        .accessibilityHint(т("fb_edit"))
    }

    // MARK: Переключатель

    /// «Вещь / Коробка / Линейка» — когда камера есть (запрет и сбой — заглушка, переключать нечего).
    @ViewBuilder
    private var переключатель: some View {
        if (Config.габаритыЛинейка || модель.вещь.доступна) && !модель.замерВещи && модель.камера != .запрещена
            && модель.камера != .сбой {
            ПереключательРежимаГабаритов(режим: модель.режим, сВещью: модель.вещь.доступна) { новый in
                модель.сменитьРежим(новый)
            }
            .frame(maxWidth: модель.вещь.доступна ? 440 : 360)
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
    }

    // MARK: Подсказки

    private var подсказки: some View {
        VStack(spacing: 8) {
            if модель.режим == .линейка && модель.камера == .идёт {
                ПодсказкаЛинейкиГабаритов(линейка: модель.линейка)
            } else if let подсказка = модель.подсказка {
                пилюля(значок: подсказка.значок, текст: подсказка.текст)
                    .id(подсказка.текст)
                    .transition(.opacity)
            }
            if let сообщение = модель.сообщение {
                Text(сообщение)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.black)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Theme.шапкаМята,
                                in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
        }
        .padding(.top, 10)
        .padding(.horizontal, 20)
        .animation(ДвижениеСайта.смена, value: модель.подсказка?.текст)
        .animation(ДвижениеСайта.смена, value: модель.сообщение)
    }

    private func пилюля(значок: String, текст: String) -> some View {
        HStack(spacing: 10) {
            значокПодсказки(значок)
                .accessibilityHidden(true)
            Text(текст)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    /// Значок подсказки; «ведите телефоном» — телефон покачивается из стороны в сторону (при «Уменьшении движения» —
    /// стоит).
    @ViewBuilder
    private func значокПодсказки(_ значок: String) -> some View {
        let картинка = Image(systemName: значок)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.шапкаМята)
        if значок == "iphone" && !тихо {
            картинка.phaseAnimator([false, true]) { вид, фаза in
                вид
                    .offset(x: фаза ? 5 : -5)
                    .rotationEffect(.degrees(фаза ? 8 : -8))
            } animation: { _ in
                .easeInOut(duration: 0.8)
            }
        } else {
            картинка
        }
    }

    // MARK: Низ

    @ViewBuilder
    private var низ: some View {
        if модель.камера != .запрещена && модель.камера != .сбой {
            if модель.режим == .линейка {
                ПанельЛинейкиГабаритов(линейка: модель.линейка, можно: модель.камера == .идёт) {
                    модель.снятьЛинейку()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            } else {
                низКоробки
            }
        }
    }

    private var низКоробки: some View {
        VStack(spacing: 12) {
            if модель.режим == .вещь {
                ПлашкаВещиГабаритов(вещь: модель.вещь)
                    .transition(.opacity)
            }
            if модель.стенаДоступна {
                кнопкаСтены
                    .transition(.opacity)
            }
            HStack(alignment: .center, spacing: 8) {
                боковая(значок: "arrow.counterclockwise", подпись: т("fb_reset"), озвучка: т("fb_reset_a11y"),
                        можно: модель.этап == .стоит) {
                    модель.убрать()
                }
                кнопкаСнимка
                боковая(значок: "ruler", подпись: т("fb_sizes"), озвучка: т("fb_edit"), можно: true) {
                    ОткликСайта.выбор()
                    модель.листРазмеров = true
                }
            }
            Text(т("fb_note"))
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .shadow(color: Color.black.opacity(0.6), radius: 3)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .animation(ДвижениеСайта.смена, value: модель.стенаДоступна)
        .animation(ДвижениеСайта.смена, value: модель.режим)
    }

    private func боковая(значок: String, подпись: String, озвучка: String, можно: Bool,
                         действие: @escaping () -> Void) -> some View {
        Button(action: действие) {
            VStack(spacing: 4) {
                Image(systemName: значок)
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.45), in: Circle())
                    .overlay { Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 1) }
                Text(подпись)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .shadow(color: Color.black.opacity(0.6), radius: 3)
            }
            .foregroundStyle(Color.white)
            .opacity(можно ? 1 : 0.4)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.92))
        .disabled(!можно)
        .accessibilityLabel(озвучка)
    }

    private var кнопкаСнимка: some View {
        let можно = модель.этап == .стоит && !модель.снимаем
        return Button {
            ОткликСайта.выбор()
            модель.снять()
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(Color.white, lineWidth: 4)
                    .frame(width: затвор, height: затвор)
                Circle()
                    .fill(можно ? Theme.зелёныйЯркий : Color.white.opacity(0.3))
                    .frame(width: затвор - 14, height: затвор - 14)
                if модель.снимаем {
                    SiteSpinner(размер: 24, толщина: 3, дорожка: Color.white.opacity(0.25), верх: Color.white,
                                стоит: тихо)
                } else {
                    Image(systemName: "camera.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.black.opacity(0.8))
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.92))
        .disabled(!можно)
        .accessibilityLabel(т("fb_shot"))
        .accessibilityHint(т("fb_shot_a11y"))
    }

    private var кнопкаСтены: some View {
        let прижато = модель.прижато
        return Button {
            модель.переключитьСтену()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: прижато ? "checkmark.circle.fill" : "arrow.up.to.line")
                    .font(.subheadline.weight(.bold))
                    .accessibilityHidden(true)
                Text(т("fb_wall"))
                    .font(.subheadline.weight(.bold))
            }
            .foregroundStyle(прижато ? Color.black : Color.white)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(прижато ? AnyShapeStyle(Theme.зелёныйЯркий) : AnyShapeStyle(Color.black.opacity(0.5)),
                        in: Capsule())
            .overlay { Capsule().strokeBorder(Theme.шапкаМята.opacity(прижато ? 0 : 0.6), lineWidth: 1) }
            .contentShape(Capsule())
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.95))
        .accessibilityLabel(т("fb_wall"))
        .accessibilityHint(т("fb_wall_hint"))
        .accessibilityAddTraits(прижато ? .isSelected : [])
    }

    // MARK: Без AR

    /// AR на устройстве нет: размеры крупно — сравнить с местом рулеткой, и «Изменить размеры».
    private var безAR: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "cube.transparent")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(Theme.шапкаМята)
                    .accessibilityHidden(true)
                Text(т("fb_no_ar"))
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(т("fb_no_ar_hint"))
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .opacity(0.8)
                if let габариты = модель.габариты {
                    таблица(габариты)
                }
                Button {
                    ОткликСайта.выбор()
                    модель.листРазмеров = true
                } label: {
                    Text(т("fb_edit"))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 22)
                        .frame(minHeight: 46)
                        .background(Theme.зелёныйЯркий, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(НажатиеКнопкиФото(сжатие: 0.96))
                Text(т("fb_note"))
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .opacity(0.7)
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 28)
            .padding(.top, 32)
            .padding(.bottom, 40)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }

    private func таблица(_ габариты: ГабаритыВещи) -> some View {
        VStack(spacing: 0) {
            строкаТаблицы(значок: "arrow.left.and.right", подпись: т("fb_w"), значение: габариты.ширина)
            Divider().overlay(Color.white.opacity(0.12))
            строкаТаблицы(значок: "arrow.up.and.down", подпись: т("fb_h"), значение: габариты.высота)
            Divider().overlay(Color.white.opacity(0.12))
            строкаТаблицы(значок: "arrow.up.left.and.arrow.down.right", подпись: т("fb_d"), значение: габариты.глубина)
        }
        .padding(.horizontal, 16)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
    }

    private func строкаТаблицы(значок: String, подпись: String, значение: Double) -> some View {
        HStack(spacing: 12) {
            Image(systemName: значок)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.шапкаМята)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(подпись)
                .font(.body)
            Spacer(minLength: 8)
            Text(ГабаритыВещи.число(значение) + " " + т("fb_cm"))
                .font(.title3.weight(.bold).monospacedDigit())
        }
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }
}
