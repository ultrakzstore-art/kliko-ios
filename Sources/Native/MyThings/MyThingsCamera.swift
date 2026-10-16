import SwiftUI
import PhotosUI
import UIKit

/**
 «МОЁ» — СЪЁМКА ПО ШАБЛОНУ (владелец 14.10.2026: «чел фоткает по шаблону свою тачку»; «полный рост сфоткал по шаблону»).

 Тёмная студия во весь экран. Камера — та же, что у поиска по фото и примерочной (КамераПоиска, ПревьюКамерыПоиска):
 доступ спрашивается только здесь, по нажатию «Снять по шаблону»; уходит приложение в фон — камера останавливается.
 Поверх — контур примерочной (КонтурПримерочной: машина сбоку или человек в полный рост — свечение, пунктир, «дыхание»,
 линия сканера), три совета выезжают по очереди, подсказка в капсуле, внизу «Галерея» · затвор · «Другая камера».
   · Машина сбоку — только задняя камера. Где стоял контур в миг снимка, запоминается (рамка фигуры и размер превью):
     по ним кольца колёс сразу встают на колёса снимка (ОбработкаФотоМоего.колёса).
   · Полный рост — передняя или задняя камера, таймер 3 или 10 с (10 — поставить телефон и отойти), крупный отсчёт.
 Нет доступа или камеры — заглушка «Выбрать из галереи» и «Открыть Настройки». Галерея — системный выбор фото вне
 приложения, разрешения на фото не нужно. Снимок проверяется на следующем шаге (ПроверкаСнимкаМоего) и только по
 «Сохранить на телефоне» ложится в «Моё»; в Фото iPhone и на сервер ничего не уходит. «Уменьшение движения» и лёгкий
 режим — контур неподвижен, без вспышки и пружин.
 */
struct КамераШаблонаМоего: View {
    let шаблон: ШаблонСъёмкиМоего
    let начатьСГалереи: Bool
    let сохранить: @MainActor (СнимокМоего) async -> Bool
    @Environment(\.dismiss) private var закрыть
    @Environment(\.accessibilityReduceMotion) private var меньшеДвижения
    @Environment(\.scenePhase) private var фаза
    @ObservedObject private var режим = РежимУстройства.shared
    @StateObject private var камера = КамераПоиска()
    @State private var снимок: СнимокМоего? = nil
    @State private var выбор: PhotosPickerItem? = nil
    @State private var галерея = false
    @State private var камераВключена = false
    @State private var вспышка = false
    @State private var таймер = 0
    @State private var отсчёт: Int? = nil
    @State private var задачаОтсчёта: Task<Void, Never>? = nil
    @State private var готовим = false
    @State private var весть: String? = nil
    @State private var номерВести = 0
    @State private var местоПревью: CGRect = .zero
    @State private var местоКонтура: CGRect = .zero
    @State private var виден = false
    @State private var вФоне = false

    private static let ширинаКнопки: CGFloat = 88

    init(шаблон: ШаблонСъёмкиМоего, начатьСГалереи: Bool = false,
         сохранить: @escaping @MainActor (СнимокМоего) async -> Bool) {
        self.шаблон = шаблон
        self.начатьСГалереи = начатьСГалереи
        self.сохранить = сохранить
    }

    private func т(_ ключ: String) -> String { МоёText.т(ключ) }

    private var тихо: Bool { меньшеДвижения || ДвижениеСайта.тихо || режим.лёгкий }

    private var живая: Bool { камераВключена && (камера.доступ == .есть || камера.доступ == .неизвестно) }

    var body: some View {
        ZStack {
            ФонПримерочной()
            if let снимок {
                ПроверкаСнимкаМоего(снимок: снимок, шаблон: шаблон, тихо: тихо, сохранить: сохранить,
                                    переснять: { переснять() }, закрыть: { закрыть() })
                    .transition(.opacity)
            } else {
                съёмка
                    .transition(.opacity)
            }
            if готовим {
                готовимВид
                    .transition(.opacity)
            }
            if let весть {
                VStack {
                    Spacer()
                    ВестьПримерочной(текст: весть)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 150)
                }
                .transition(.opacity)
                .allowsHitTesting(false)
            }
        }
        .environment(\.colorScheme, .dark)
        .animation(ДвижениеСайта.смена, value: снимок == nil)
        .animation(ДвижениеСайта.появление, value: готовим)
        .photosPicker(isPresented: $галерея, selection: $выбор, matching: .images)
        .onChange(of: выбор) { _, новый in загрузить(новый) }
        .onChange(of: галерея) { _, открыта in
            if !открыта { галереяЗакрыта() }
        }
        .onAppear {
            виден = true
            if начатьСГалереи {
                /* Выбор фото — после того, как окно встало: два показа сразу система не принимает. */
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    if виден && снимок == nil { галерея = true }
                }
            } else {
                включитьКамеру()
            }
        }
        .onDisappear {
            виден = false
            задачаОтсчёта?.cancel()
            задачаОтсчёта = nil
            отсчёт = nil
            камера.остановить()
        }
        .onChange(of: фаза) { _, новая in сменаФазы(новая) }
    }

    // MARK: Съёмка

    private var съёмка: some View {
        ZStack {
            фон
            Color.white
                .opacity(вспышка ? 0.8 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            if let отсчёт {
                Text(String(отсчёт))
                    .font(.system(size: 120, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.white)
                    .shadow(color: Theme.зелёныйЯркий.opacity(0.9), radius: 24)
                    .id(отсчёт)
                    .transition(тихо ? AnyTransition.opacity
                                     : AnyTransition.scale(scale: 1.6).combined(with: AnyTransition.opacity))
                    .accessibilityHidden(true)
            }
            VStack(spacing: 0) {
                верх
                if живая {
                    советы
                        .padding(.top, 10)
                        .padding(.horizontal, 16)
                }
                Spacer(minLength: 12)
                if живая {
                    подсказка
                        .padding(.horizontal, 24)
                        .padding(.bottom, 10)
                }
                низ
            }
        }
    }

    @ViewBuilder
    private var фон: some View {
        if !камераВключена {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
        } else {
            switch камера.доступ {
            case .есть, .неизвестно:
                ПревьюКамерыПоиска(камера: камера)
                    .background { замер { местоПревью = $0 } }
                    .ignoresSafeArea()
                    .opacity(камера.готова ? 1 : 0)
                    .animation(ДвижениеСайта.появление, value: камера.готова)
                    .accessibilityHidden(true)
                КонтурПримерочной(тихо: тихо, вид: шаблон.вид)
                    .background { замер { местоКонтура = $0 } }
                    .padding(.top, 130)
                    .padding(.bottom, 200)
                    .padding(.horizontal, 24)
                    .allowsHitTesting(false)
            case .запрещён:
                заглушка(заголовок: т("my_cam_denied"), текст: т("my_cam_denied_hint"), настройки: true)
            case .нетКамеры:
                заглушка(заголовок: т("my_cam_no_cam"), текст: т("my_cam_no_cam_hint"), настройки: false)
            }
        }
    }

    /// Невидимый замер места в координатах окна — при появлении и при каждой смене.
    private func замер(_ запомнить: @escaping (CGRect) -> Void) -> some View {
        GeometryReader { г in
            Color.clear
                .onAppear { запомнить(г.frame(in: .global)) }
                .onChange(of: г.frame(in: .global)) { _, новое in запомнить(новое) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Контур машины в миг снимка — в координатах превью. Не измерен или тело — nil.
    private var рамкаШаблона: РамкаШаблонаМоего? {
        guard !шаблон.тело, местоПревью.width > 0, местоПревью.height > 0, местоКонтура.width > 0 else { return nil }
        let фигура = СилуэтМашиныПримерочной.рамка(в: местоКонтура.size)
        let контур = фигура.offsetBy(dx: местоКонтура.minX - местоПревью.minX, dy: местоКонтура.minY - местоПревью.minY)
        return РамкаШаблонаМоего(контур: контур, вид: местоПревью.size)
    }

    // MARK: Верх, советы, подсказка

    private var верх: some View {
        HStack(spacing: 12) {
            КруглаяКнопкаФото(значок: "xmark", подпись: т("my_close")) { закрыть() }
            Spacer(minLength: 0)
            Text(шаблон.заголовок)
                .font(.headline)
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .shadow(color: Color.black.opacity(0.5), radius: 3)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if живая && шаблон.тело {
                КруглаяКнопкаФото(значок: "timer", подпись: т("my_cam_timer"), активна: таймер > 0) {
                    сменитьТаймер()
                }
                .overlay(alignment: .bottomTrailing) {
                    if таймер > 0 {
                        Text(String(таймер))
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 4)
                            .background(Color.white, in: Capsule())
                            .offset(x: 4, y: 4)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityValue(таймер > 0 ? String(format: т("my_cam_timer_n"), String(таймер)) : т("my_cam_timer_off"))
            } else {
                Color.clear
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private var советы: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { фишки }
            VStack(spacing: 6) { фишки }
        }
    }

    private var фишки: some View {
        ForEach(Array(шаблон.советы.enumerated()), id: \.offset) { пара in
            ФишкаСоветаПримерочной(значок: пара.element.значок, текст: пара.element.текст, номер: пара.offset,
                                   тихо: тихо)
        }
    }

    private var подсказка: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.зелёныйЯркий)
                    .accessibilityHidden(true)
                Text(шаблон.подсказка)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if шаблон.тело {
                Text(т("my_cam_self"))
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.75))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.5), in: Capsule())
        .overlay { Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1) }
    }

    // MARK: Низ: «Галерея», затвор, «Другая камера»

    private var низ: some View {
        HStack(alignment: .top, spacing: 0) {
            кнопкаНиза(значок: "photo.on.rectangle", подпись: т("my_cam_gallery"), доступна: !готовим) {
                ОткликСайта.выбор()
                галерея = true
            }
            Spacer(minLength: 8)
            if живая {
                затвор
            }
            Spacer(minLength: 8)
            if живая && шаблон.тело && камера.естьПередняя {
                кнопкаНиза(значок: "arrow.triangle.2.circlepath.camera", подпись: т("my_cam_flip"),
                           доступна: камера.готова) {
                    ОткликСайта.выбор()
                    камера.переключитьКамеру()
                }
            } else {
                Color.clear
                    .frame(width: Self.ширинаКнопки, height: 1)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background {
            LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.65)], startPoint: .top,
                           endPoint: .bottom)
                .ignoresSafeArea()
        }
    }

    private func подписьКнопки(_ текст: String) -> some View {
        Text(текст)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .shadow(color: Color.black.opacity(0.6), radius: 2)
    }

    private func кнопкаНиза(значок: String, подпись: String, доступна: Bool,
                            действие: @escaping () -> Void) -> some View {
        Button(action: действие) {
            VStack(spacing: 6) {
                Image(systemName: значок)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 56, height: 56)
                    .background(Color.black.opacity(0.45), in: Circle())
                    .overlay { Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 1.5) }
                    .frame(height: 80)
                подписьКнопки(подпись)
            }
            .frame(width: Self.ширинаКнопки)
            .contentShape(Rectangle())
            .opacity(доступна ? 1 : 0.4)
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.92))
        .disabled(!доступна)
        .accessibilityLabel(подпись)
    }

    /// Большой затвор: белое кольцо и круг; во время снимка и отсчёта круг зеленеет.
    private var затвор: some View {
        Button { нажатьЗатвор() } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 5)
                        .frame(width: 80, height: 80)
                    Circle()
                        .fill(камера.снимаем || отсчёт != nil ? Theme.зелёныйЯркий : Color.white)
                        .frame(width: 64, height: 64)
                    if таймер > 0 {
                        Image(systemName: "timer")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.7))
                            .accessibilityHidden(true)
                    }
                }
                подписьКнопки(т("my_cam_shoot"))
            }
            .frame(width: 96)
            .contentShape(Rectangle())
            .opacity(камера.готова ? 1 : 0.4)
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.9))
        .disabled(!камера.готова || камера.снимаем || отсчёт != nil || готовим)
        .accessibilityLabel(т("my_cam_shoot_a11y"))
        .accessibilityValue(таймер > 0 ? String(format: т("my_cam_timer_n"), String(таймер)) : "")
    }

    private var готовимВид: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                SiteSpinner(размер: 34, толщина: 3.5, дорожка: Color.white.opacity(0.15), верх: Theme.зелёныйЯркий,
                            стоит: ДвижениеСайта.тихо)
                Text(т("my_cam_preparing"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// Нет доступа или камеры: значок, объяснение, «Выбрать из галереи» и (если запрещено) «Открыть Настройки».
    private func заглушка(заголовок: String, текст: String, настройки: Bool) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                Image(systemName: шаблон.значок)
                    .font(.system(size: 32, weight: .semibold))
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
                Text(текст)
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 24)
                ЗелёнаяКнопкаФото(заголовок: т("my_cam_pick"), значок: "photo.on.rectangle") {
                    галерея = true
                }
                .padding(.bottom, 10)
                if настройки {
                    ЗелёнаяКнопкаФото(заголовок: т("my_cam_settings"), значок: "gearshape", контурная: true,
                                      наТёмном: true) {
                        if let адрес = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(адрес)
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 120)
            .padding(.bottom, 140)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Действия

    private func включитьКамеру() {
        камераВключена = true
        камера.запустить()
    }

    /// Таймер полного роста: выкл → 3 с → 10 с → выкл.
    private func сменитьТаймер() {
        ОткликСайта.выбор()
        таймер = таймер == 0 ? 3 : (таймер == 3 ? 10 : 0)
        let слово = таймер > 0 ? String(format: т("my_cam_timer_n"), String(таймер)) : т("my_cam_timer_off")
        UIAccessibility.post(notification: .announcement, argument: слово)
    }

    private func нажатьЗатвор() {
        guard камера.готова, !камера.снимаем, отсчёт == nil, !готовим else { return }
        guard таймер > 0 else {
            снять()
            return
        }
        let секунд = таймер
        задачаОтсчёта?.cancel()
        задачаОтсчёта = Task { @MainActor in
            for число in stride(from: секунд, through: 1, by: -1) {
                withAnimation(тихо ? nil : .spring(response: 0.32, dampingFraction: 0.68)) { отсчёт = число }
                if число <= 3 {
                    UISelectionFeedbackGenerator().selectionChanged()
                    UIAccessibility.post(notification: .announcement, argument: String(число))
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled {
                    отсчёт = nil
                    return
                }
            }
            withAnimation(тихо ? nil : .easeOut(duration: 0.15)) { отсчёт = nil }
            снять()
        }
    }

    private func снять() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if !тихо {
            вспышка = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 60_000_000)
                withAnimation(.easeOut(duration: 0.3)) { вспышка = false }
            }
        }
        let рамка = рамкаШаблона
        камера.снять { кадр in
            обработать(.кадр(кадр), рамка: рамка)
        }
    }

    /// Снимок или файл → готовое фото и разбор (Vision) вне главной нити → шаг проверки.
    private func обработать(_ источник: ИсточникСнимкаМоего, рамка: РамкаШаблонаМоего?) {
        готовим = true
        let тело = шаблон.тело
        Task { @MainActor in
            let итог = await Task.detached(priority: .userInitiated) { () -> СнимокМоего? in
                ОбработкаФотоМоего.снимок(источник, тело: тело, рамка: рамка)
            }.value
            готовим = false
            guard виден else { return }
            guard let итог else {
                ОткликСайта.предупреждение()
                показатьВесть(т("my_photo_bad"))
                return
            }
            камера.остановить()
            withAnimation(тихо ? nil : ДвижениеСайта.смена) { снимок = итог }
            UIAccessibility.post(notification: .screenChanged, argument: nil)
        }
    }

    private func загрузить(_ элемент: PhotosPickerItem?) {
        guard let элемент else { return }
        выбор = nil
        готовим = true
        Task { @MainActor in
            guard let данные = try? await элемент.loadTransferable(type: Data.self) else {
                готовим = false
                ОткликСайта.предупреждение()
                показатьВесть(т("my_photo_bad"))
                return
            }
            обработать(.файл(данные), рамка: nil)
        }
    }

    /// Начали с галереи и закрыли её, ничего не выбрав, — окно закрывается (камеру не включали и доступ не спрашивали).
    private func галереяЗакрыта() {
        guard начатьСГалереи, !камераВключена else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            if снимок == nil && !готовим && выбор == nil && !галерея && !камераВключена { закрыть() }
        }
    }

    private func переснять() {
        снимок = nil
        if камераВключена {
            камера.запустить()
        } else {
            включитьКамеру()
        }
    }

    private func сменаФазы(_ новая: ScenePhase) {
        guard виден, камераВключена, снимок == nil else { return }
        switch новая {
        case .background:
            вФоне = true
            задачаОтсчёта?.cancel()
            отсчёт = nil
            камера.остановить()
        case .active:
            guard вФоне else { return }
            вФоне = false
            камера.запустить()
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    private func показатьВесть(_ текст: String) {
        номерВести += 1
        let номер = номерВести
        withAnimation(ДвижениеСайта.появление) { весть = текст }
        UIAccessibility.post(notification: .announcement, argument: текст)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard номер == номерВести else { return }
            withAnimation(ДвижениеСайта.уход) { весть = nil }
        }
    }
}
