import SwiftUI
import UIKit
import AVFoundation
import Vision
import VisionKit

/**
 СКАНЕР МАРКИРОВКИ КОЛЁС КАМЕРОЙ (владелец 16.10.2026, скрин «Параметры колёс»: «стандартизация должна быть необычной, а
 прям по диску + камерой узнать размеры по диаметру»).

 Кто зовёт: поля «Параметры колёс» (гараж «Моё» и «Подойдут ли?») — кнопкой сканера у шины и у диска:
 СканерКолёс.открыть(что: .шина или .диск) { маркировка in … }. Если СканерКолёс.доступен — false (нет камеры), кнопки
 быть не должно. Окно — во весь экран поверх верхнего экрана (верхний контроллер — ПоверхВсего.верхний(), как у «Поместится
 ли?»: камера — не лист, смахивание листа спорило бы с наведением), всегда тёмное. Ничего не сохраняется и не
 отправляется: кадры живут только в памяти телефона, пока открыто окно.

 Камера:
   · VisionKit (DataScannerViewController, iOS 16+), если устройство умеет и доступ дан (isSupported и isAvailable), —
     живое распознавание текста: надписи подсвечиваются, прочитанное 4 раза в секунду идёт в разбор
     (РазборМаркировкиКолеса, WheelScanParse.swift), голоса кадров копит СборМаркировкиКолеса; нажатие на подсвеченную
     надпись весит больше кадра;
   · иначе — свой AVCapture и затвор «Снять»: один кадр → Vision (VNRecognizeTextRequest: .accurate, en и ru, без
     языковой правки); не нашли — второй проход перевёрнутым кадром (надпись на шине бывает вверх ногами).
 Сверху — ✕, заголовок и фонарик (на боковине шины часто темно: через 5 с без находки — подсказка «Темно? Включите
 фонарик», кольцо у кнопки), под ними — подсказка «Наведите на боковину шины — надпись вида 205/55 R16» или «… диска —
 6.5Jx16 ET45 5x114.3», посредине — прицел с бегущей линией. Внизу — чипы полей: ещё не найдено — пунктир и «—»,
 найдено — зелёный чип «205/55 R16 ✓» вспыхивает, с откликом под пальцем и озвучкой VoiceOver; нажатие на найденный чип
 убирает его (прочитано неверно — это значение больше не вернётся). «Готово» активна, когда найдено хоть что-то:
 готово(маркировка) и окно закрывается; ✕ — закрыть без ответа. Доступ к камере запрещён — объяснение и «Открыть
 Настройки» (как в других камерах приложения); камера не включилась — объяснение и «Закрыть». «Уменьшение движения» —
 без бегущей линии, пульса и вспышки чипов.
 */
enum ЧтоСканироватьКолеса: Sendable {
    /// Боковина шины: «205/55 R16».
    case шина
    /// Внутренняя сторона диска: «6.5Jx16 ET45 5x114.3 DIA 67.1».
    case диск
}

@MainActor
enum СканерКолёс {
    private static var последнееОткрытие: Date? = nil

    /// Есть ли камера (симулятор и устройство без камеры — нет). false — кнопки сканера быть не должно.
    static var доступен: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    /**
     Открыть сканер поверх того, что на экране (во весь экран). готово — только по «Готово», с тем, что нашли (не пусто;
     поля — только для `что`: у шины — размер, у диска — диаметр, ширина, вылет, разболтовка, отверстие). Защита от
     двойного нажатия: второе окно за секунду не кладём поверх первого.
     */
    static func открыть(что: ЧтоСканироватьКолеса, готово: @escaping (МаркировкаКолеса) -> Void) {
        guard доступен else { return }
        let сейчас = Date()
        if let прежнее = последнееОткрытие, сейчас.timeIntervalSince(прежнее) < 1 { return }
        последнееОткрытие = сейчас
        Task { @MainActor in
            for попытка in 0..<12 {
                if let верх = ПоверхВсего.верхний() {
                    let хост = UIHostingController<AnyView>(rootView: AnyView(EmptyView()))
                    let закрыть: () -> Void = { [weak хост] in
                        хост?.dismiss(animated: true)
                    }
                    хост.rootView = AnyView(ЭкранСканераКолёс(что: что, готово: готово, закрыть: закрыть))
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
}

// MARK: - Модель

@MainActor
final class МодельСканераКолёс: ObservableObject {
    enum Режим: Equatable {
        /// Спрашиваем доступ к камере.
        case проверка
        /// VisionKit читает живьём.
        case живой
        /// Своя камера и затвор.
        case кадр
        case запрещено
        case нетКамеры
    }

    let что: ЧтоСканироватьКолеса
    let камера = КамераКадраКолёс()

    @Published private(set) var режим: Режим = .проверка
    /// Что нашли (только поля для `что`).
    @Published private(set) var найдено = МаркировкаКолеса()
    /// Поле, которое нашлось только что: его чип вспыхивает.
    @Published private(set) var свежее: ПолеМаркировкиКолеса? = nil
    @Published private(set) var фонарик = false
    @Published private(set) var фонарикЕсть = false
    /// 5 с без находки при выключенном фонарике — подсказка «Темно? Включите фонарик».
    @Published private(set) var темно = false
    /// Своя камера: сессия запущена, затвор можно нажимать.
    @Published private(set) var камераГотова = false
    /// Своя камера: снимок читается.
    @Published private(set) var читаем = false
    /// Своя камера: на последнем снимке маркировки не нашли.
    @Published private(set) var неПрочитали = false

    private var сбор = СборМаркировкиКолеса()
    private var гашение: Task<Void, Never>? = nil
    private var закрыто = false

    init(что: ЧтоСканироватьКолеса) {
        self.что = что
    }

    var поля: [ПолеМаркировкиКолеса] { МаркировкаКолеса.поля(что) }
    var естьНайденное: Bool { !найдено.пусто }
    var можноСнять: Bool { режим == .кадр && камераГотова && !читаем }

    /// Показали окно: доступ к камере (не спрашивали — спросим), затем живой сканер или своя камера.
    func подготовить() async {
        guard режим == .проверка else { return }
        guard СканерКолёс.доступен else {
            режим = .нетКамеры
            return
        }
        /* Доступ спрашиваем здесь: без него VisionKit считает сканер недоступным. */
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        guard !закрыто else { return }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            режим = .запрещено
            return
        }
        if КамераТекстаКолёс.можно {
            режим = .живой
            фонарикЕсть = ФонарикКолёс.есть
        } else {
            запуститьКадр()
        }
        следитьЗаТемнотой()
    }

    private func запуститьКадр() {
        режим = .кадр
        камераГотова = false
        камера.запустить { [weak self] вышло in
            guard let self, !self.закрыто else { return }
            self.камераГотова = вышло
            self.фонарикЕсть = вышло && ФонарикКолёс.есть
            if !вышло { self.режим = .нетКамеры }
        }
    }

    /// Живой сканер перестал работать (камеру забрали, ограничения) — дальше снимками.
    func живойНедоступен() {
        guard режим == .живой, !закрыто else { return }
        выключитьФонарик()
        запуститьКадр()
    }

    private func следитьЗаТемнотой() {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self, !self.закрыто, self.найдено.пусто, self.фонарикЕсть, !self.фонарик else { return }
            withAnimation(ДвижениеСайта.появление) { self.темно = true }
        }
    }

    /**
     Строки, прочитанные камерой; вес — сколько голосов (кадр живой камеры — 1, снимок — 2, нажатие на надпись — 4).
     true — в строках нашлось что-то для `что`.
     */
    @discardableResult
    func прочитано(_ строки: [String], вес: Int) -> Bool {
        guard !закрыто, !строки.isEmpty else { return false }
        let м = РазборМаркировкиКолеса.разобрать(строки).для(что)
        guard !м.пусто else { return false }
        сбор.добавить(м, вес: вес)
        обновить()
        return true
    }

    /// Нажали найденный чип: прочитано неверно — убрать, это значение больше не принимать.
    func убрать(_ поле: ПолеМаркировкиКолеса) {
        guard let запись = найдено.подпись(поле) else { return }
        сбор.убрать(поле)
        ОткликСайта.выбор()
        обновить()
        объявить(СканерКолёсText.т("ws_removed_a11y", запись))
    }

    private func обновить() {
        let новое = сбор.итог.для(что)
        guard новое != найдено else { return }
        let прежнее = найдено
        let появилось = поля.first(where: { новое.есть($0) && !прежнее.есть($0) })
        withAnimation(ДвижениеСайта.мягко(.spring(response: 0.42, dampingFraction: 0.62))) {
            найдено = новое
            if let появилось {
                свежее = появилось
                темно = false
            }
        }
        guard let новоеПоле = появилось, let запись = новое.подпись(новоеПоле) else { return }
        ОткликСайта.успех()
        объявить(СканерКолёсText.т("ws_found_a11y", запись))
        гашение?.cancel()
        гашение = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard let self, !Task.isCancelled else { return }
            withAnimation(ДвижениеСайта.смена) { self.свежее = nil }
        }
    }

    private func объявить(_ текст: String) {
        UIAccessibility.post(notification: .announcement, argument: текст)
    }

    func переключитьФонарик() {
        let включить = !фонарик
        guard ФонарикКолёс.включить(включить) else { return }
        фонарик = включить
        ОткликСайта.выбор()
        if включить && темно {
            withAnimation(ДвижениеСайта.уход) { темно = false }
        }
    }

    private func выключитьФонарик() {
        guard фонарик else { return }
        ФонарикКолёс.включить(false)
        фонарик = false
    }

    /// Затвор своей камеры: снимок → Vision (не на главной нити) → разбор.
    func снять() {
        guard можноСнять else { return }
        читаем = true
        withAnimation(ДвижениеСайта.смена) { неПрочитали = false }
        let что = self.что
        камера.снять { [weak self] снимок in
            guard let self else { return }
            guard let снимок, !self.закрыто else {
                self.читаем = false
                return
            }
            Task { [weak self] in
                let строки = await ЧтениеКадраКолёс.строки(из: снимок, что: что)
                guard let self, !self.закрыто else { return }
                let нашли = self.прочитано(строки, вес: 2)
                self.читаем = false
                if !нашли {
                    withAnimation(ДвижениеСайта.смена) { self.неПрочитали = true }
                    ОткликСайта.предупреждение()
                }
            }
        }
    }

    /// Окно уходит: фонарик гаснет, своя камера останавливается.
    func остановить() {
        закрыто = true
        гашение?.cancel()
        выключитьФонарик()
        камера.остановить()
    }
}

// MARK: - Экран

struct ЭкранСканераКолёс: View {
    @StateObject private var модель: МодельСканераКолёс
    private let готово: (МаркировкаКолеса) -> Void
    private let закрыть: () -> Void
    @Environment(\.accessibilityReduceMotion) private var меньшеДвижения

    init(что: ЧтоСканироватьКолеса, готово: @escaping (МаркировкаКолеса) -> Void, закрыть: @escaping () -> Void) {
        _модель = StateObject(wrappedValue: МодельСканераКолёс(что: что))
        self.готово = готово
        self.закрыть = закрыть
    }

    private func т(_ ключ: String) -> String { СканерКолёсText.т(ключ) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            камера
            if модель.режим == .живой || модель.режим == .кадр {
                ПрицелКолёс(тихо: меньшеДвижения, нашли: модель.естьНайденное)
            }
            switch модель.режим {
            case .запрещено:
                заглушка(значок: "camera.fill", заголовок: т("ws_no_access_t"), текст: т("ws_no_access_s"),
                         настройки: true)
            case .нетКамеры:
                заглушка(значок: "video.slash.fill", заголовок: т("ws_no_cam_t"), текст: т("ws_no_cam_s"),
                         настройки: false)
            case .проверка:
                ожидание
            case .живой, .кадр:
                слой
            }
        }
        .task { await модель.подготовить() }
        .onDisappear { модель.остановить() }
    }

    // MARK: Камера

    @ViewBuilder
    private var камера: some View {
        switch модель.режим {
        case .живой:
            живаяКамера(модель)
                .ignoresSafeArea()
        case .кадр:
            ПревьюКадраКолёс(камера: модель.камера)
                .ignoresSafeArea()
                .overlay {
                    if модель.читаем {
                        Color.black.opacity(0.35)
                            .ignoresSafeArea()
                            .transition(.opacity)
                    }
                }
        default:
            EmptyView()
        }
    }

    /// Живой сканер; ответы — прямо в модель (не через обёртку StateObject экрана).
    private func живаяКамера(_ м: МодельСканераКолёс) -> some View {
        КамераТекстаКолёс(прочитано: { строки, вес in
                              _ = м.прочитано(строки, вес: вес)
                          },
                          недоступна: {
                              м.живойНедоступен()
                          })
    }

    // MARK: Слой поверх камеры

    private var слой: some View {
        VStack(spacing: 0) {
            верх
            подсказка
                .padding(.top, 12)
                .padding(.horizontal, 16)
            Spacer(minLength: 0)
            низ
        }
    }

    private var ожидание: some View {
        VStack(spacing: 0) {
            верх
            Spacer(minLength: 0)
            SiteSpinner(размер: 28, толщина: 3, дорожка: Color.white.opacity(0.15), верх: Theme.зелёныйЯркий,
                        стоит: меньшеДвижения)
            Spacer(minLength: 0)
        }
    }

    private var верх: some View {
        HStack(spacing: 12) {
            круглаяКнопка(значок: "xmark", подпись: т("ws_close"), активна: false, зовёт: false, действие: закрыть)
            Spacer(minLength: 0)
            VStack(spacing: 1) {
                Text(т(модель.что == .шина ? "ws_title_tire" : "ws_title_rim"))
                    .font(.headline)
                    .foregroundStyle(Color.white)
                Text(т("ws_sub"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.шапкаМята)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .shadow(color: Color.black.opacity(0.5), radius: 3)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if модель.фонарикЕсть {
                круглаяКнопка(значок: модель.фонарик ? "flashlight.on.fill" : "flashlight.off.fill",
                              подпись: т(модель.фонарик ? "ws_torch_off" : "ws_torch_on"), активна: модель.фонарик,
                              зовёт: модель.темно) {
                    модель.переключитьФонарик()
                }
            } else {
                Color.clear
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    /// Подсказка наведения — капсулой; в темноте под ней — «Темно? Включите фонарик» (нажатие включает).
    private var подсказка: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "text.viewfinder")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.зелёныйЯркий)
                    .accessibilityHidden(true)
                Text(т(модель.что == .шина ? "ws_hint_tire" : "ws_hint_rim"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.55), in: Capsule())
            .overlay { Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1) }
            .accessibilityElement(children: .combine)
            if модель.темно && !модель.фонарик {
                Button {
                    модель.переключитьФонарик()
                } label: {
                    Label(т("ws_dark"), systemImage: "flashlight.on.fill")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Theme.зелёныйЯркий, in: Capsule())
                }
                .buttonStyle(НажатиеКнопкиСканераКолёс())
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // MARK: Низ: состояние, чипы, затвор, «Готово»

    private var низ: some View {
        VStack(spacing: 12) {
            состояние
            ПереносЧиповКолёс(промежуток: 8) {
                ForEach(модель.поля, id: \.self) { поле in
                    чип(поле)
                }
            }
            if модель.режим == .кадр {
                затвор
            }
            широкаяКнопка(т("ws_done"), значок: "checkmark", доступна: модель.естьНайденное) {
                let итог = модель.найдено
                guard !итог.пусто else { return }
                ОткликСайта.успех()
                готово(итог)
                закрыть()
            }
            .accessibilityHint(т("ws_done_a11y"))
            Text(т("ws_private"))
                .font(.caption2)
                .foregroundStyle(Color.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
        .padding(.top, 40)
        .padding(.bottom, 10)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.8)], startPoint: .top,
                           endPoint: .bottom)
                .ignoresSafeArea()
        }
    }

    private var текстСостояния: String {
        if модель.читаем { return т("ws_reading") }
        if модель.режим == .кадр && модель.неПрочитали { return т("ws_not_read") }
        if модель.естьНайденное { return т("ws_found") }
        if модель.режим == .кадр { return т("ws_shot_hint") }
        return т("ws_searching")
    }

    private var состояние: some View {
        HStack(spacing: 8) {
            if модель.читаем {
                SiteSpinner(размер: 14, толщина: 2, дорожка: Color.white.opacity(0.2), верх: Theme.зелёныйЯркий,
                            стоит: меньшеДвижения)
            } else if модель.режим == .кадр && модель.неПрочитали {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.yellow)
                    .accessibilityHidden(true)
            } else if модель.естьНайденное {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Theme.зелёныйЯркий)
                    .accessibilityHidden(true)
            } else {
                ТочкаПоискаКолёс(тихо: меньшеДвижения)
            }
            Text(текстСостояния)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .shadow(color: Color.black.opacity(0.6), radius: 3)
        .animation(ДвижениеСайта.смена, value: текстСостояния)
        .accessibilityElement(children: .combine)
    }

    private func название(_ поле: ПолеМаркировкиКолеса) -> String {
        switch поле {
        case .шина: return т("ws_f_tire")
        case .диаметр: return т("ws_f_r")
        case .ширина: return т("ws_f_j")
        case .вылет: return т("ws_f_et")
        case .разболтовка: return т("ws_f_pcd")
        case .ступица: return т("ws_f_dia")
        }
    }

    /// Чип поля: ищем — пунктир и «—»; нашли — зелёный «205/55 R16 ✓», только что — вспышка. Нажатие на найденный — убрать.
    private func чип(_ поле: ПолеМаркировкиКолеса) -> some View {
        let запись = модель.найдено.подпись(поле)
        let есть = запись != nil
        let свежий = модель.свежее == поле && !меньшеДвижения
        let подпись = запись.map { название(поле) + ": " + $0 } ?? СканерКолёсText.т("ws_wait_a11y", название(поле))
        return Button {
            модель.убрать(поле)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(название(поле))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(есть ? Color.black.opacity(0.62) : Color.white.opacity(0.62))
                HStack(spacing: 5) {
                    Text(запись ?? "—")
                        .font(.system(.subheadline, design: .rounded, weight: .heavy))
                        .monospacedDigit()
                    if есть {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.footnote.weight(.bold))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .foregroundStyle(есть ? Color.black : Color.white.opacity(0.85))
            }
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minWidth: 84, alignment: .leading)
            .background(есть ? AnyShapeStyle(Theme.зелёныйЯркий) : AnyShapeStyle(Color.black.opacity(0.5)),
                        in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                    .strokeBorder(Color.white.opacity(есть ? 0 : 0.35), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
            }
            .shadow(color: Theme.зелёныйЯркий.opacity(свежий ? 0.9 : 0), radius: свежий ? 14 : 0)
            .scaleEffect(свежий ? 1.08 : 1)
        }
        .buttonStyle(НажатиеКнопкиСканераКолёс())
        .disabled(!есть)
        .accessibilityLabel(подпись)
        .accessibilityHint(есть ? т("ws_remove_hint") : "")
    }

    /// Затвор своей камеры: белое кольцо и круг; пока читаем — круг зеленеет и крутится колесо.
    private var затвор: some View {
        Button {
            модель.снять()
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 4)
                        .frame(width: 74, height: 74)
                    Circle()
                        .fill(модель.читаем ? Theme.зелёныйЯркий : Color.white)
                        .frame(width: 60, height: 60)
                    if модель.читаем {
                        SiteSpinner(размер: 24, толщина: 3, дорожка: Color.black.opacity(0.15),
                                    верх: Color.black.opacity(0.7), стоит: меньшеДвижения)
                    } else {
                        Image(systemName: "text.viewfinder")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.6))
                            .accessibilityHidden(true)
                    }
                }
                Text(т("ws_shot"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white)
            }
            .opacity(модель.можноСнять || модель.читаем ? 1 : 0.4)
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеКнопкиСканераКолёс(сжатие: 0.9))
        .disabled(!модель.можноСнять)
        .accessibilityLabel(т("ws_shot_a11y"))
    }

    // MARK: Нет доступа или камеры

    private func заглушка(значок: String, заголовок: String, текст: String, настройки: Bool) -> some View {
        VStack(spacing: 0) {
            верх
            ScrollView {
                VStack(spacing: 0) {
                    Image(systemName: значок)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Theme.зелёныйЯркий)
                        .frame(width: 80, height: 80)
                        .background(Color.white.opacity(0.1), in: Circle())
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
                        .foregroundStyle(Color.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 24)
                    if настройки {
                        широкаяКнопка(т("ws_settings"), значок: "gearshape") {
                            if let адрес = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(адрес, options: [:], completionHandler: nil)
                            }
                        }
                        .padding(.bottom, 10)
                    }
                    широкаяКнопка(т("ws_close"), значок: "xmark", контурная: true, действие: закрыть)
                }
                .padding(.horizontal, 32)
                .padding(.top, 80)
                .padding(.bottom, 60)
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Кнопки

    /// Круглая кнопка 44 pt на тёмной подложке; включённая (фонарик) — зелёная; зовёт — вокруг бежит кольцо.
    private func круглаяКнопка(значок: String, подпись: String, активна: Bool, зовёт: Bool,
                               действие: @escaping () -> Void) -> some View {
        Button(action: действие) {
            Image(systemName: значок)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(активна ? Color.black : Color.white)
                .frame(width: 44, height: 44)
                .background(активна ? AnyShapeStyle(Theme.зелёныйЯркий) : AnyShapeStyle(Color.black.opacity(0.45)),
                            in: Circle())
                .overlay { Circle().strokeBorder(Color.white.opacity(активна ? 0 : 0.16), lineWidth: 1) }
                .overlay {
                    if зовёт {
                        КольцоЗоваКолёс(тихо: меньшеДвижения)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(НажатиеКнопкиСканераКолёс(сжатие: 0.92))
        .accessibilityLabel(подпись)
        .accessibilityAddTraits(активна ? .isSelected : [])
    }

    /// Кнопка во всю ширину: зелёная заливка или белый контур; недоступная — бледная.
    private func широкаяКнопка(_ заголовок: String, значок: String, контурная: Bool = false, доступна: Bool = true,
                               действие: @escaping () -> Void) -> some View {
        Button(action: действие) {
            HStack(spacing: 10) {
                Image(systemName: значок)
                    .font(.body.weight(.bold))
                    .accessibilityHidden(true)
                Text(заголовок)
                    .font(.body.weight(.bold))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 16)
            .background {
                RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                    .fill(контурная ? AnyShapeStyle(Color.clear)
                          : (доступна ? AnyShapeStyle(Theme.зелёный2) : AnyShapeStyle(Color.white.opacity(0.14))))
            }
            .overlay {
                if контурная {
                    RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.55), lineWidth: 1.5)
                }
            }
            .opacity(доступна ? 1 : 0.6)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .animation(ДвижениеСайта.смена, value: доступна)
        }
        .buttonStyle(НажатиеКнопкиСканераКолёс())
        .disabled(!доступна)
    }
}

// MARK: - Оформление

/// Лёгкое сжатие под пальцем — остаётся и при «Уменьшении движения» (как НажатиеКнопкиФото).
struct НажатиеКнопкиСканераКолёс: ButtonStyle {
    var сжатие: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? сжатие : 1)
            .animation(ДвижениеСайта.нажатие, value: configuration.isPressed)
    }
}

/// Кольцо, которое расходится от кнопки фонарика, когда темно; при «Уменьшении движения» — стоит.
private struct КольцоЗоваКолёс: View {
    let тихо: Bool
    @State private var идёт = false

    var body: some View {
        Circle()
            .strokeBorder(Theme.зелёныйЯркий, lineWidth: 2)
            .scaleEffect(тихо ? 1.12 : (идёт ? 1.55 : 1))
            .opacity(тихо ? 0.9 : (идёт ? 0 : 0.9))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                guard !тихо else { return }
                withAnimation(.easeOut(duration: 1.3).repeatForever(autoreverses: false)) { идёт = true }
            }
    }
}

/// Пульсирующая точка «ищем»; при «Уменьшении движения» — просто точка.
private struct ТочкаПоискаКолёс: View {
    let тихо: Bool
    @State private var идёт = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.зелёныйЯркий.opacity(0.4))
                .scaleEffect(тихо ? 0.6 : (идёт ? 1 : 0.4))
                .opacity(тихо ? 0.5 : (идёт ? 0 : 1))
            Circle()
                .fill(Theme.зелёныйЯркий)
                .frame(width: 8, height: 8)
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
        .onAppear {
            guard !тихо else { return }
            withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) { идёт = true }
        }
    }
}

/**
 Прицел посреди камеры: полоса под надпись (широкая — маркировка идёт строкой), зелёные уголки и бегущая линия. Нашли
 хоть что-то — рамка светится. Касания проходят сквозь прицел к камере (нажатие на подсвеченную надпись).
 */
private struct ПрицелКолёс: View {
    let тихо: Bool
    let нашли: Bool
    @State private var бег = false

    var body: some View {
        GeometryReader { место in
            let ширина = max(0, min(место.size.width - 48, 520))
            let высота = max(96, min(ширина * 0.36, 180))
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.зелёныйЯркий.opacity(нашли ? 0.08 : 0))
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                УголкиПрицелаКолёс(длина: 26, радиус: 18)
                    .stroke(нашли ? Theme.зелёныйЯркий : Color.white.opacity(0.9),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    .shadow(color: Theme.зелёныйЯркий.opacity(нашли ? 0.7 : 0), radius: 8)
                if !тихо {
                    LinearGradient(colors: [Theme.зелёныйЯркий.opacity(0), Theme.зелёныйЯркий.opacity(0.9),
                                            Theme.зелёныйЯркий.opacity(0)],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(height: 2)
                        .shadow(color: Theme.зелёныйЯркий.opacity(0.8), radius: 6)
                        .padding(.horizontal, 16)
                        .offset(y: бег ? высота / 2 - 14 : -высота / 2 + 14)
                        .opacity(0.85)
                }
            }
            .frame(width: ширина, height: высота)
            .position(x: место.size.width / 2, y: место.size.height * 0.4)
            .animation(ДвижениеСайта.смена, value: нашли)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !тихо else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { бег = true }
        }
    }
}

/// Четыре уголка рамки со скруглением.
private struct УголкиПрицелаКолёс: Shape {
    let длина: CGFloat
    let радиус: CGFloat

    func path(in прямоугольник: CGRect) -> Path {
        let д = min(длина, прямоугольник.width / 2, прямоугольник.height / 2)
        let р = min(радиус, д)
        let л = прямоугольник.minX
        let п = прямоугольник.maxX
        let в = прямоугольник.minY
        let н = прямоугольник.maxY
        var путь = Path()
        /* левый верхний */
        путь.move(to: CGPoint(x: л, y: в + д))
        путь.addLine(to: CGPoint(x: л, y: в + р))
        путь.addQuadCurve(to: CGPoint(x: л + р, y: в), control: CGPoint(x: л, y: в))
        путь.addLine(to: CGPoint(x: л + д, y: в))
        /* правый верхний */
        путь.move(to: CGPoint(x: п - д, y: в))
        путь.addLine(to: CGPoint(x: п - р, y: в))
        путь.addQuadCurve(to: CGPoint(x: п, y: в + р), control: CGPoint(x: п, y: в))
        путь.addLine(to: CGPoint(x: п, y: в + д))
        /* правый нижний */
        путь.move(to: CGPoint(x: п, y: н - д))
        путь.addLine(to: CGPoint(x: п, y: н - р))
        путь.addQuadCurve(to: CGPoint(x: п - р, y: н), control: CGPoint(x: п, y: н))
        путь.addLine(to: CGPoint(x: п - д, y: н))
        /* левый нижний */
        путь.move(to: CGPoint(x: л + д, y: н))
        путь.addLine(to: CGPoint(x: л + р, y: н))
        путь.addQuadCurve(to: CGPoint(x: л, y: н - р), control: CGPoint(x: л, y: н))
        путь.addLine(to: CGPoint(x: л, y: н - д))
        return путь
    }
}

/// Чипы рядами по центру: не влез — на следующий ряд.
struct ПереносЧиповКолёс: Layout {
    var промежуток: CGFloat = 8

    private struct Ряд {
        var номера: [Int] = []
        var ширина: CGFloat = 0
        var высота: CGFloat = 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let доступно = proposal.width ?? .infinity
        let ряды = разложить(subviews, ширина: доступно)
        let высота = ряды.reduce(CGFloat(0)) { $0 + $1.высота } + промежуток * CGFloat(max(0, ряды.count - 1))
        let широчайший = ряды.map { $0.ширина }.max() ?? 0
        return CGSize(width: proposal.width ?? широчайший, height: высота)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for ряд in разложить(subviews, ширина: bounds.width) {
            var x = bounds.minX + max(0, (bounds.width - ряд.ширина) / 2)
            for номер in ряд.номера {
                let размер = subviews[номер].sizeThatFits(.unspecified)
                subviews[номер].place(at: CGPoint(x: x, y: y + (ряд.высота - размер.height) / 2),
                                      proposal: ProposedViewSize(размер))
                x += размер.width + промежуток
            }
            y += ряд.высота + промежуток
        }
    }

    private func разложить(_ subviews: Subviews, ширина: CGFloat) -> [Ряд] {
        var итог: [Ряд] = []
        var текущий = Ряд()
        for номер in subviews.indices {
            let размер = subviews[номер].sizeThatFits(.unspecified)
            if !текущий.номера.isEmpty && текущий.ширина + промежуток + размер.width > ширина {
                итог.append(текущий)
                текущий = Ряд()
            }
            текущий.ширина += (текущий.номера.isEmpty ? 0 : промежуток) + размер.width
            текущий.высота = max(текущий.высота, размер.height)
            текущий.номера.append(номер)
        }
        if !текущий.номера.isEmpty { итог.append(текущий) }
        return итог
    }
}

// MARK: - Живой сканер (VisionKit)

/// DataScannerViewController: текст, точное распознавание, все надписи кадра, подсветка найденного, щипок — увеличение.
struct КамераТекстаКолёс: UIViewControllerRepresentable {
    /// Строки и вес: кадр — 1, нажатие на подсвеченную надпись — 4.
    let прочитано: ([String], Int) -> Void
    /// Сканер перестал работать — модель перейдёт на снимки.
    let недоступна: () -> Void

    /// Устройство умеет и доступ к камере дан.
    @MainActor
    static var можно: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        /* Маркировка — латиницей; русский — чтобы «ЕТ», «ЦО» и кириллица продавца не рассыпались. */
        let поддержка = DataScannerViewController.supportedTextRecognitionLanguages
        let языки = ["en-US", "ru-RU"].filter { поддержка.contains($0) }
        let сканер = DataScannerViewController(recognizedDataTypes: [.text(languages: языки)],
                                               qualityLevel: .accurate,
                                               recognizesMultipleItems: true,
                                               isHighFrameRateTrackingEnabled: false,
                                               isPinchToZoomEnabled: true,
                                               isGuidanceEnabled: false,
                                               isHighlightingEnabled: true)
        сканер.delegate = context.coordinator
        сканер.view.backgroundColor = .black
        return сканер
    }

    func updateUIViewController(_ сканер: DataScannerViewController, context: Context) {
        context.coordinator.прочитано = прочитано
        context.coordinator.недоступна = недоступна
        guard !сканер.isScanning else { return }
        /* Экран ещё может въезжать: запуск — на следующем обороте, повторный вызов безвреден. */
        Task { @MainActor in
            if !сканер.isScanning { try? сканер.startScanning() }
        }
    }

    static func dismantleUIViewController(_ сканер: DataScannerViewController, coordinator: Координатор) {
        сканер.stopScanning()
    }

    func makeCoordinator() -> Координатор {
        Координатор(прочитано: прочитано, недоступна: недоступна)
    }

    @MainActor
    final class Координатор: NSObject, DataScannerViewControllerDelegate {
        var прочитано: ([String], Int) -> Void
        var недоступна: () -> Void
        /// Когда отдали кадр в последний раз: не чаще 4 раз в секунду.
        private var отдали = Date.distantPast

        init(прочитано: @escaping ([String], Int) -> Void, недоступна: @escaping () -> Void) {
            self.прочитано = прочитано
            self.недоступна = недоступна
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            отдать(allItems, сразу: true)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            отдать(allItems, сразу: false)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            if case .text(let текст) = item {
                прочитано([текст.transcript], 4)
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            недоступна()
        }

        private func отдать(_ все: [RecognizedItem], сразу: Bool) {
            let сейчас = Date()
            guard сразу || сейчас.timeIntervalSince(отдали) >= 0.25 else { return }
            отдали = сейчас
            var строки: [String] = []
            for вещь in все {
                if case .text(let текст) = вещь { строки.append(текст.transcript) }
            }
            if !строки.isEmpty { прочитано(строки, 1) }
        }
    }
}

// MARK: - Своя камера (без VisionKit)

/**
 Задняя камера для снимка надписи: сессия AVFoundation живёт на своей очереди (запуск, поворот, снимок, остановка);
 наружу — только ответы на главной нити. Фокус — ближний план: маркировку снимают с 15–30 см.
 */
final class КамераКадраКолёс: NSObject, AVCapturePhotoCaptureDelegate {
    let сессия = AVCaptureSession()
    private let очередь = DispatchQueue(label: "kz.kliko.wheelscan.camera")
    private let выход = AVCapturePhotoOutput()
    /// Только на очереди камеры.
    private var настроена = false
    private var угол: CGFloat = 90
    private var готово: (@MainActor (UIImage?) -> Void)? = nil

    override init() {
        super.init()
    }

    /// Запустить сессию; ответ — на главной нити: true — кадры пошли.
    func запустить(_ ответ: @escaping @MainActor (Bool) -> Void) {
        очередь.async { [weak self] in
            guard let self else { return }
            if !self.настроена { self.настроена = self.настроить() }
            let вышло = self.настроена
            if вышло && !self.сессия.isRunning { self.сессия.startRunning() }
            Task { @MainActor in ответ(вышло) }
        }
    }

    /// На очереди камеры: задняя широкая камера, выход снимков, фокус ближнего плана.
    private func настроить() -> Bool {
        guard let устройство = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let вход = try? AVCaptureDeviceInput(device: устройство) else { return false }
        сессия.beginConfiguration()
        сессия.sessionPreset = .photo
        guard сессия.canAddInput(вход), сессия.canAddOutput(выход) else {
            сессия.commitConfiguration()
            return false
        }
        сессия.addInput(вход)
        сессия.addOutput(выход)
        сессия.commitConfiguration()
        if (try? устройство.lockForConfiguration()) != nil {
            if устройство.isAutoFocusRangeRestrictionSupported { устройство.autoFocusRangeRestriction = .near }
            if устройство.isFocusModeSupported(.continuousAutoFocus) { устройство.focusMode = .continuousAutoFocus }
            устройство.unlockForConfiguration()
        }
        return true
    }

    /// Поворот превью (главная нить сообщает его снимку).
    func повернуть(_ новый: CGFloat) {
        очередь.async { [weak self] in
            self?.угол = новый
        }
    }

    /// Окно уходит: сессия останавливается (фонарик гасит модель).
    func остановить() {
        /* Сильная ссылка: окно уже закрыто — сессия всё равно гаснет, а не ждёт освобождения. */
        очередь.async {
            if self.сессия.isRunning { self.сессия.stopRunning() }
        }
    }

    /// Затвор: снимок (или nil — не вышло) придёт на главной нити.
    func снять(_ ответ: @escaping @MainActor (UIImage?) -> Void) {
        очередь.async { [weak self] in
            guard let self else { return }
            /* Без живой видеосвязи capturePhoto бросает исключение — не снимаем. */
            guard self.готово == nil, self.сессия.isRunning, let связь = self.выход.connection(with: .video),
                  связь.isActive, связь.isEnabled else {
                Task { @MainActor in ответ(nil) }
                return
            }
            if связь.isVideoRotationAngleSupported(self.угол) {
                связь.videoRotationAngle = self.угол
            }
            self.готово = ответ
            self.выход.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        let снимок = error == nil ? photo.fileDataRepresentation().flatMap { UIImage(data: $0) } : nil
        очередь.async { [weak self] in
            guard let self, let действие = self.готово else { return }
            self.готово = nil
            Task { @MainActor in действие(снимок) }
        }
    }
}

/// Превью своей камеры во весь экран: AVCaptureVideoPreviewLayer с заполнением, поворот — по интерфейсу.
struct ПревьюКадраКолёс: UIViewRepresentable {
    let камера: КамераКадраКолёс

    final class Вид: UIView {
        weak var камера: КамераКадраКолёс?

        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var слой: AVCaptureVideoPreviewLayer? { layer as? AVCaptureVideoPreviewLayer }

        override func layoutSubviews() {
            super.layoutSubviews()
            let угол: CGFloat
            switch window?.windowScene?.interfaceOrientation ?? .portrait {
            case .portraitUpsideDown: угол = 270
            case .landscapeLeft: угол = 180
            case .landscapeRight: угол = 0
            default: угол = 90
            }
            if let связь = слой?.connection, связь.isVideoRotationAngleSupported(угол), связь.videoRotationAngle != угол {
                связь.videoRotationAngle = угол
            }
            камера?.повернуть(угол)
        }
    }

    func makeUIView(context: Context) -> Вид {
        let вид = Вид()
        вид.backgroundColor = .black
        вид.камера = камера
        вид.слой?.session = камера.сессия
        вид.слой?.videoGravity = .resizeAspectFill
        return вид
    }

    func updateUIView(_ uiView: Вид, context: Context) {
        uiView.setNeedsLayout()
    }
}

/// Чтение снимка: Vision, точное распознавание, en и ru, без языковой правки (это коды, а не слова). Не на главной нити.
enum ЧтениеКадраКолёс {
    /// Строки снимка (по три варианта каждой надписи). Ничего для `что` — второй проход перевёрнутым кадром.
    static func строки(из снимок: UIImage, что: ЧтоСканироватьКолеса) async -> [String] {
        await withCheckedContinuation { (продолжение: CheckedContinuation<[String], Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                продолжение.resume(returning: ЧтениеКадраКолёс.прочитать(снимок, что: что))
            }
        }
    }

    private static func прочитать(_ снимок: UIImage, что: ЧтоСканироватьКолеса) -> [String] {
        guard let кадр = снимок.cgImage else { return [] }
        let поворот = ориентация(снимок.imageOrientation)
        let первые = распознать(кадр, поворот)
        if !РазборМаркировкиКолеса.разобрать(первые).для(что).пусто { return первые }
        return первые + распознать(кадр, перевёрнутая(поворот))
    }

    private static func распознать(_ кадр: CGImage, _ ориентация: CGImagePropertyOrientation) -> [String] {
        let запрос = VNRecognizeTextRequest()
        запрос.recognitionLevel = .accurate
        запрос.usesLanguageCorrection = false
        запрос.minimumTextHeight = 0.02
        let поддержка = (try? запрос.supportedRecognitionLanguages()) ?? []
        let языки = ["en-US", "ru-RU"].filter { поддержка.contains($0) }
        if !языки.isEmpty { запрос.recognitionLanguages = языки }
        let обработчик = VNImageRequestHandler(cgImage: кадр, orientation: ориентация, options: [:])
        do {
            try обработчик.perform([запрос])
        } catch {
            return []
        }
        var итог: [String] = []
        for наблюдение in запрос.results ?? [] {
            for кандидат in наблюдение.topCandidates(3) { итог.append(кандидат.string) }
        }
        return итог
    }

    private static func ориентация(_ о: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch о {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }

    /// Та же ориентация, повёрнутая на 180°.
    private static func перевёрнутая(_ о: CGImagePropertyOrientation) -> CGImagePropertyOrientation {
        switch о {
        case .up: return .down
        case .down: return .up
        case .left: return .right
        case .right: return .left
        case .upMirrored: return .downMirrored
        case .downMirrored: return .upMirrored
        case .leftMirrored: return .rightMirrored
        case .rightMirrored: return .leftMirrored
        @unknown default: return .down
        }
    }
}

/// Фонарик задней камеры — и под VisionKit, и под своей камерой (светодиод один).
enum ФонарикКолёс {
    private static var устройство: AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }

    static var есть: Bool {
        guard let у = устройство else { return false }
        return у.hasTorch && у.isTorchModeSupported(.on)
    }

    /// true — фонарик в нужном положении.
    @discardableResult
    static func включить(_ вкл: Bool) -> Bool {
        guard let у = устройство, у.hasTorch, у.isTorchModeSupported(вкл ? .on : .off) else { return false }
        if вкл && !у.isTorchAvailable { return false }
        guard (try? у.lockForConfiguration()) != nil else { return false }
        у.torchMode = вкл ? .on : .off
        у.unlockForConfiguration()
        return true
    }
}
