import PhotosUI
import SwiftUI
import UIKit

/**
 3D-ОБЗОР В ПОДАЧЕ — ОКНО СЪЁМКИ (владелец 14.10.2026: «5 разных фото, и ИИ сам собрал 3D любой вещи или авто»).

 Полноэкранное, всегда тёмное (как примерочная и камера поиска): глубокий зелёно-чёрный фон, белый текст, зелёный
 акцент. Съёмка — живая камера поиска (КамераПоиска, задняя), сверху — подсказка ракурса: схема обхода сверху (вещь в
 центре, пять мест камеры, стрелка к текущему) и «Обойдите вещь — шаг 2 из 5: под углом 45° спереди-слева». После
 снимка — вырезка общим движком студии и проверка с галочкой, «Переснять». По пяти кадрам — обзор с поворотом пальцем
 и «Собрать 3D»; сборка — ракурсы встают в кольцо и кружат, проценты; готово — постер и «Посмотреть в 3D».
 Шаги — МодельСъёмкиОбзора3D; сборка и её ход — ХранилищеОбзора3DПодачи. При «Уменьшении движения» ничего не летает и
 не кружит, в лёгком режиме (РежимУстройства.лёгкий) кольцо стоит.
 */
struct ЭкранСъёмкиОбзора3D: View {
    let закрыть: () -> Void
    @StateObject private var модель: МодельСъёмкиОбзора3D
    @StateObject private var камера = КамераПоиска()
    @ObservedObject private var хранилище = ХранилищеОбзора3DПодачи.shared

    init(подача: ПодачаМодель, вид: ВидОбзора3DПодачи, закрыть: @escaping () -> Void) {
        self.закрыть = закрыть
        _модель = StateObject(wrappedValue: МодельСъёмкиОбзора3D(подача: подача, вид: вид))
    }

    /// Что на экране: шаг модели, а в обзоре — ещё и ход сборки из хранилища.
    enum Экран: Hashable {
        case съёмка, проверка, обзор, сборка, готово
    }

    private var экран: Экран {
        switch модель.шаг {
        case .съёмка: return .съёмка
        case .проверка: return .проверка
        case .обзор:
            guard let з = модель.запись else { return .обзор }
            if з.собирается || хранилище.запускаем.contains(модель.ключ) { return .сборка }
            if з.готова { return .готово }
            return .обзор
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ФонПримерочной()
            содержимое
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(экран)
                .transition(.opacity)
            if let весть = модель.весть {
                ВестьПримерочной(текст: весть)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .environment(\.colorScheme, .dark)
        .animation(ДвижениеСайта.шаг, value: экран)
        .onAppear {
            модель.открыт()
            if экран == .готово { модель.загрузитьПостер() }
        }
        .onDisappear { модель.закрыть() }
        .onChange(of: экран) { _, новый in
            UIAccessibility.post(notification: .screenChanged, argument: nil)
            if новый == .готово { модель.загрузитьПостер() }
        }
    }

    @ViewBuilder
    private var содержимое: some View {
        switch экран {
        case .съёмка:
            ШагКамерыОбзора3D(модель: модель, камера: камера, закрыть: закрыть)
        case .проверка:
            ШагПроверкиОбзора3D(модель: модель, закрыть: закрыть)
        case .обзор:
            ШагОбзораРакурсов3D(модель: модель, закрыть: закрыть)
        case .сборка:
            ШагСборкиОбзора3D(модель: модель, закрыть: закрыть)
        case .готово:
            ШагГотовоОбзора3D(модель: модель, закрыть: закрыть)
        }
    }
}

// MARK: - Камера

/// Съёмка ракурса: живая камера, подсказка ракурса со схемой, советы, полоска пяти ракурсов, затвор и галерея.
struct ШагКамерыОбзора3D: View {
    @ObservedObject var модель: МодельСъёмкиОбзора3D
    @ObservedObject var камера: КамераПоиска
    let закрыть: () -> Void
    @ObservedObject private var хранилище = ХранилищеОбзора3DПодачи.shared
    @ObservedObject private var режим = РежимУстройства.shared
    @Environment(\.accessibilityReduceMotion) private var меньшеДвижения
    @Environment(\.scenePhase) private var фаза
    @State private var выбор: PhotosPickerItem? = nil
    @State private var галерея = false
    @State private var вспышка = false
    @State private var виден = false
    @State private var вФоне = false

    private static let ширинаКнопки: CGFloat = 88

    init(модель: МодельСъёмкиОбзора3D, камера: КамераПоиска, закрыть: @escaping () -> Void) {
        self.модель = модель
        self.камера = камера
        self.закрыть = закрыть
    }

    private func т(_ ключ: String) -> String { Обзор3DПодачиText.т(ключ) }

    private var тихо: Bool { меньшеДвижения || ДвижениеСайта.тихо }

    private var живая: Bool { камера.доступ == .есть || камера.доступ == .неизвестно }

    private var снятые: Set<Int> {
        guard let з = модель.запись else { return [] }
        return Set(РакурсОбзора3DПодачи.allCases.filter { з.ракурс($0).есть }.map { $0.rawValue })
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            фон
            Color.white
                .opacity(вспышка ? 0.8 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            VStack(spacing: 0) {
                верх
                ПодсказкаРакурсаОбзора3D(вид: модель.вид, ракурс: модель.ракурс, снятые: снятые,
                                         тихо: тихо || режим.лёгкий)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                if живая {
                    советы
                        .padding(.top, 10)
                        .padding(.horizontal, 16)
                }
                Spacer(minLength: 12)
                ПолоскаРакурсовОбзора3D(кадры: модель.кадры, запись: модель.запись, текущий: модель.ракурс.rawValue,
                                        плохой: хранилище.отказЗагрузки[модель.ключ]?.ракурс, малая: true, нажать: nil)
                    .padding(.horizontal, 24)
                низ
            }
            if модель.готовим {
                ZStack {
                    Color.black.opacity(0.6)
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        SiteSpinner(размер: 34, толщина: 3.5, дорожка: Color.white.opacity(0.15),
                                    верх: Theme.зелёныйЯркий)
                        Text(т("m3_cutting"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.white)
                    }
                    .accessibilityElement(children: .combine)
                }
                .transition(.opacity)
            }
        }
        .photosPicker(isPresented: $галерея, selection: $выбор, matching: .images)
        .onChange(of: выбор) { _, новый in загрузить(новый) }
        .onAppear {
            виден = true
            камера.запустить()
        }
        .onDisappear {
            виден = false
            камера.остановить()
        }
        .onChange(of: фаза) { _, новая in
            guard виден else { return }
            switch новая {
            case .background:
                вФоне = true
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
    }

    // MARK: Фон: превью и рамка, или заглушка

    @ViewBuilder
    private var фон: some View {
        switch камера.доступ {
        case .есть, .неизвестно:
            ПревьюКамерыПоиска(камера: камера)
                .ignoresSafeArea()
                .opacity(камера.готова ? 1 : 0)
                .animation(ДвижениеСайта.появление, value: камера.готова)
                .accessibilityHidden(true)
            УголкиОбзора3D()
                .stroke(Theme.зелёныйЯркий.opacity(0.9), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .shadow(color: Color.black.opacity(0.4), radius: 4)
                .padding(.top, 240)
                .padding(.bottom, 230)
                .padding(.horizontal, 36)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        case .запрещён:
            заглушка(заголовок: т("m3_denied"), текст: т("m3_denied_hint"), настройки: true)
        case .нетКамеры:
            заглушка(заголовок: т("m3_no_cam"), текст: т("m3_no_cam_hint"), настройки: false)
        }
    }

    // MARK: Верх: ✕, заголовок и шаг, фонарик

    private var верх: some View {
        HStack(spacing: 12) {
            КруглаяКнопкаФото(значок: "xmark", подпись: т("m3_close"), действие: закрыть)
            Spacer(minLength: 0)
            VStack(spacing: 1) {
                Text(т("m3_title"))
                    .font(.headline)
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(String(format: т("m3_step_n"), модель.ракурс.номер, РакурсОбзора3DПодачи.всего))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.шапкаМята)
                    .lineLimit(1)
            }
            .shadow(color: Color.black.opacity(0.5), radius: 3)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if живая && камера.фонарикЕсть {
                КруглаяКнопкаФото(значок: камера.фонарик ? "flashlight.on.fill" : "flashlight.off.fill",
                                  подпись: т("m3_torch"), активна: камера.фонарик) {
                    ОткликСайта.выбор()
                    камера.переключитьФонарик()
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

    /// Три совета — фишками; не влезают в строку — столбиком.
    private var советы: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { фишки }
            VStack(spacing: 6) { фишки }
        }
    }

    private var фишки: some View {
        let машины: [(значок: String, ключ: String)] = [("car", "m3_tip_car_whole"), ("figure.walk", "m3_tip_car_far"),
                                                          ("person.fill.xmark", "m3_tip_no_people")]
        let вещи: [(значок: String, ключ: String)] = [("cube", "m3_tip_whole"), ("square.dashed", "m3_tip_bg"),
                                                        ("sun.max", "m3_tip_light")]
        let список = модель.вид == .машина ? машины : вещи
        return ForEach(Array(список.enumerated()), id: \.offset) { пара in
            ФишкаСоветаПримерочной(значок: пара.element.значок, текст: т(пара.element.ключ), номер: пара.offset,
                                   тихо: тихо)
        }
    }

    // MARK: Низ: «Галерея», затвор, «К обзору»

    private var низ: some View {
        HStack(alignment: .top, spacing: 0) {
            кнопкаНиза(значок: "photo.on.rectangle", подпись: т("m3_gallery"), доступна: !модель.готовим) {
                галерея = true
            }
            Spacer(minLength: 8)
            затвор
            Spacer(minLength: 8)
            if модель.можноКОбзору {
                кнопкаНиза(значок: "rotate.3d", подпись: т("m3_to_review"), доступна: !модель.готовим) {
                    модель.кОбзору()
                }
            } else {
                Color.clear
                    .frame(width: Self.ширинаКнопки, height: 1)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
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

    /// Большой затвор: белое кольцо и круг с номером ракурса; во время снимка круг зеленеет.
    private var затвор: some View {
        Button { снять() } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 5)
                        .frame(width: 80, height: 80)
                    Circle()
                        .fill(камера.снимаем ? Theme.зелёныйЯркий : Color.white)
                        .frame(width: 64, height: 64)
                    Text(String(модель.ракурс.номер))
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.75))
                        .accessibilityHidden(true)
                }
                подписьКнопки(т("m3_shoot"))
            }
            .frame(width: 96)
            .contentShape(Rectangle())
            .opacity(камера.готова ? 1 : 0.4)
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.9))
        .disabled(!камера.готова || камера.снимаем || модель.готовим)
        .accessibilityLabel(String(format: т("m3_shoot_a11y"), модель.ракурс.номер, РакурсОбзора3DПодачи.всего,
                                   т(модель.ракурс.ключТекста)))
    }

    // MARK: Действия

    private func снять() {
        guard камера.готова, !камера.снимаем, !модель.готовим else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if !тихо {
            вспышка = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 60_000_000)
                withAnimation(.easeOut(duration: 0.3)) { вспышка = false }
            }
        }
        камера.снять { снимок in
            модель.принять(снимок)
        }
    }

    private func загрузить(_ элемент: PhotosPickerItem?) {
        guard let элемент else { return }
        выбор = nil
        Task { @MainActor in
            guard let данные = try? await элемент.loadTransferable(type: Data.self) else {
                модель.показатьВесть(т("m3_bad_image"))
                return
            }
            модель.принять(данные: данные)
        }
    }

    /// Нет доступа или камеры: объяснение, «Выбрать из галереи» и (если запрещено) «Открыть Настройки».
    private func заглушка(заголовок: String, текст: String, настройки: Bool) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                Image(systemName: модель.вид == .машина ? "car" : "rotate.3d")
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
                ЗелёнаяКнопкаФото(заголовок: т("m3_pick"), значок: "photo.on.rectangle") {
                    галерея = true
                }
                .padding(.bottom, 10)
                if настройки {
                    ЗелёнаяКнопкаФото(заголовок: т("m3_settings"), значок: "gearshape", контурная: true,
                                      наТёмном: true) {
                        if let адрес = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(адрес)
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 260)
            .padding(.bottom, 200)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
        }
    }
}

/// Уголки рамки над камерой: «вещь — целиком внутри».
struct УголкиОбзора3D: Shape {
    func path(in место: CGRect) -> Path {
        var путь = Path()
        let длина = min(36, min(место.width, место.height) * 0.18)
        let л = место.minX
        let п = место.maxX
        let в = место.minY
        let н = место.maxY
        путь.move(to: CGPoint(x: л, y: в + длина))
        путь.addLine(to: CGPoint(x: л, y: в))
        путь.addLine(to: CGPoint(x: л + длина, y: в))
        путь.move(to: CGPoint(x: п - длина, y: в))
        путь.addLine(to: CGPoint(x: п, y: в))
        путь.addLine(to: CGPoint(x: п, y: в + длина))
        путь.move(to: CGPoint(x: п, y: н - длина))
        путь.addLine(to: CGPoint(x: п, y: н))
        путь.addLine(to: CGPoint(x: п - длина, y: н))
        путь.move(to: CGPoint(x: л + длина, y: н))
        путь.addLine(to: CGPoint(x: л, y: н))
        путь.addLine(to: CGPoint(x: л, y: н - длина))
        return путь
    }
}

// MARK: - Проверка снятого ракурса

/**
 Вырезка крупно на тёмной шахматке (прозрачность видна), отметка: «Вещь вырезана ✓» или «Не получилось отделить вещь от
 фона» (уйдёт как есть, фон уберёт сервер); «В кадре люди» — подсказка. «Дальше» (у последнего — «К обзору») и
 «Переснять».
 */
struct ШагПроверкиОбзора3D: View {
    @ObservedObject var модель: МодельСъёмкиОбзора3D
    let закрыть: () -> Void
    @Environment(\.accessibilityReduceMotion) private var меньшеДвижения
    @State private var появилось = false

    init(модель: МодельСъёмкиОбзора3D, закрыть: @escaping () -> Void) {
        self.модель = модель
        self.закрыть = закрыть
    }

    private func т(_ ключ: String) -> String { Обзор3DПодачиText.т(ключ) }

    private var тихо: Bool { меньшеДвижения || ДвижениеСайта.тихо }

    /// После этого ракурса снимать больше нечего (или это пересъёмка одного).
    private var последний: Bool {
        guard let з = модель.запись else { return модель.ракурс == .сзади }
        let недостаёт = РакурсОбзора3DПодачи.allCases.filter { !з.ракурс($0).есть && $0 != модель.ракурс }
        return недостаёт.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            ШапкаПримерочной(заголовок: String(format: т("m3_step_n"), модель.ракурс.номер, РакурсОбзора3DПодачи.всего),
                             закрыть: закрыть)
            ScrollView {
                VStack(spacing: 14) {
                    снимок
                    Text(т(модель.ракурс.ключТекста))
                        .font(.headline)
                        .foregroundStyle(Color.white)
                        .multilineTextAlignment(.center)
                    отметка(хорошо: модель.вырезан, значок: модель.вырезан ? "checkmark.circle.fill" : "scissors",
                            текст: т(модель.вырезан ? "m3_cut_ok" : "m3_cut_fail"))
                    if модель.людиВКадре {
                        отметка(хорошо: false, значок: "person.fill.xmark", текст: т("m3_people"))
                    }
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
                withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { появилось = true }
            }
        }
    }

    private var снимок: some View {
        ZStack(alignment: .topTrailing) {
            ШахматкаОбзора3D()
                .overlay {
                    if let картинка = модель.снимок {
                        Image(uiImage: картинка)
                            .resizable()
                            .scaledToFit()
                            .padding(14)
                            .shadow(color: Color.black.opacity(0.45), radius: 14, x: 0, y: 10)
                            .scaleEffect(появилось ? 1 : 0.88)
                    }
                }
                .aspectRatio(0.8, contentMode: .fit)
                .frame(maxHeight: 440)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                }
            if модель.вырезан {
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(Color.black)
                    .frame(width: 40, height: 40)
                    .background(Theme.зелёныйЯркий, in: Circle())
                    .overlay { Circle().strokeBorder(Color.white, lineWidth: 2.5) }
                    .padding(10)
                    .scaleEffect(появилось ? 1 : 0.3)
                    .opacity(появилось ? 1 : 0)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: т("m3_shot_a11y"), т(модель.ракурс.ключТекста)))
        .accessibilityAddTraits(.isImage)
    }

    private func отметка(хорошо: Bool, значок: String, текст: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: значок)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(хорошо ? Theme.зелёныйЯркий : Theme.оранжевый)
                .accessibilityHidden(true)
            Text(текст)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder((хорошо ? Theme.зелёныйЯркий : Theme.оранжевый).opacity(0.4), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var кнопки: some View {
        VStack(spacing: 10) {
            ЗелёнаяКнопкаФото(заголовок: т(последний ? "m3_to_review_go" : "m3_next"),
                              значок: последний ? "rotate.3d" : "arrow.right") {
                модель.оставить()
            }
            .disabled(модель.готовим)
            ЗелёнаяКнопкаФото(заголовок: т("m3_retake"), значок: "camera", контурная: true, наТёмном: true) {
                модель.переснять()
            }
            .disabled(модель.готовим)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
    }
}

/// Тёмная шахматка — под вырезкой видно, где прозрачно.
struct ШахматкаОбзора3D: View {
    var body: some View {
        Canvas { холст, размер in
            let клетка: CGFloat = 14
            let столбцов = Int((размер.width / клетка).rounded(.up))
            let строк = Int((размер.height / клетка).rounded(.up))
            холст.fill(Path(CGRect(origin: .zero, size: размер)), with: .color(Color(white: 0.13)))
            for строка in 0..<max(0, строк) {
                for столбец in 0..<max(0, столбцов) where (строка + столбец) % 2 == 0 {
                    let место = CGRect(x: CGFloat(столбец) * клетка, y: CGFloat(строка) * клетка, width: клетка,
                                       height: клетка)
                    холст.fill(Path(место), with: .color(Color(white: 0.17)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
