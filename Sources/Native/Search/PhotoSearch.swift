import SwiftUI
import PhotosUI
import UIKit

/**
 ПОИСК ПО ФОТО КАК НА САЙТЕ (владелец 26.09.2026, TestFlight 1.10: «камера распознавания не работает»).

 🔴 ПОЧЕМУ НЕ РАБОТАЛО. Камера в поле шапки (ШапкаСайта.поискПоФото) с этапа 25 не искала по фото: она открывала ленту
 сайта без главной (Config.лентаСайта, /kz/<язык>/?all=1) — считалось, что человек нажмёт там камеру ещё раз. На
 телефоне это выглядело как «нажал камеру — открылась та же лента, ничего не распозналось». Своего поиска по фото у
 приложения не было вовсе. Теперь — свой, тем же запросом, что mkPhotoSearch сайта (js/marketplace.min.js):

 • гость (getMkMe() пустой) — окно «Нужен аккаунт» с «Зарегистрируйтесь, чтобы искать по фото» (mkRegGate);
 • «Снять» (системная камера, КамераПодачи) или «Выбрать из фото» (PhotosPicker); камеры нет — сразу галерея;
 • снимок — как _mkPhotoPicked: большая сторона не больше 1024, JPEG 0,82, dataURL;
 • POST /api/photo_search.php, multipart, поле imgb64 (и csrf страницы), с куками веб-сессии (SiteSession);
 • пока ждём — окно «Распознаём фото…» с превью и бегущей полосой (_mkPhotoProgress);
 • ответ ok + query — окно закрывается, запрос встаёт в поле, раздел category (если есть) выбирается, плашка «Ищем: …»;
 • need/error «auth» — снова окно входа; иначе — ошибка сайта (error или «Не удалось распознать фото»), сети нет —
   «Нет соединения»; в окне ошибки — «Другое фото».
 */
enum ПоискПоФотоAPI {
    enum Итог: Equatable {
        case найдено(запрос: String, раздел: String)
        case нуженВход
        case отказ(String)
        case сеть
    }

    /// Как _mkPhotoPicked сайта: большая сторона не больше 1024, JPEG с качеством 0,82 → «data:image/jpeg;base64,…».
    /// Поворот снимка камеры рисование учитывает само. Пустой или битый — nil (у сайта — dataURL короче 120 знаков).
    static func сжать(_ снимок: UIImage) -> String? {
        let w = снимок.size.width * снимок.scale
        let h = снимок.size.height * снимок.scale
        guard w > 0, h > 0 else { return nil }
        let k = min(1, 1024 / max(w, h))
        let размер = CGSize(width: max(1, (w * k).rounded()), height: max(1, (h * k).rounded()))
        let формат = UIGraphicsImageRendererFormat()
        формат.scale = 1
        формат.opaque = true
        let рисовальщик = UIGraphicsImageRenderer(size: размер, format: формат)
        let готовый = рисовальщик.image { _ in
            снимок.draw(in: CGRect(origin: .zero, size: размер))
        }
        guard let данные = готовый.jpegData(compressionQuality: 0.82) else { return nil }
        let адрес = "data:image/jpeg;base64," + данные.base64EncodedString()
        return адрес.count > 120 ? адрес : nil
    }

    /// _mkPhotoSend: POST /api/photo_search.php (FormData с imgb64), куки и токен веб-сессии.
    static func отправить(_ адресФото: String) async -> Итог {
        guard let адрес = Config.url("/api/photo_search.php") else { return .сеть }
        let граница = "----KlikoPhotoSearch" + UUID().uuidString
        var тело = Data()
        func поле(_ имя: String, _ значение: String) {
            var часть = "--" + граница + "\r\n"
            часть += "Content-Disposition: form-data; name=\"" + имя + "\"\r\n\r\n"
            часть += значение + "\r\n"
            тело.append(Data(часть.utf8))
        }
        поле("imgb64", адресФото)
        if let csrf = await SiteSession.csrf() { поле("csrf", csrf) }
        тело.append(Data(("--" + граница + "--\r\n").utf8))

        var запрос = URLRequest(url: адрес)
        запрос.httpMethod = "POST"
        запрос.timeoutInterval = 60
        запрос.httpShouldHandleCookies = false
        запрос.setValue("multipart/form-data; boundary=" + граница, forHTTPHeaderField: "Content-Type")
        запрос.setValue("application/json", forHTTPHeaderField: "Accept")
        /* Как fetch страницы: POST того же сайта несёт Origin сайта. */
        запрос.setValue(Config.apiBase.absoluteString, forHTTPHeaderField: "Origin")
        let куки = await SiteSession.куки()
        for (имя, значение) in куки { запрос.setValue(значение, forHTTPHeaderField: имя) }
        запрос.httpBody = тело

        let данные: Data
        let ответ: URLResponse
        do {
            (данные, ответ) = try await URLSession.shared.data(for: запрос)
        } catch {
            return .сеть
        }
        let код = (ответ as? HTTPURLResponse)?.statusCode ?? 200
        /* Не JSON — «Не удалось распознать фото» (t._bad у сайта); 401/403 без тела — вход. */
        guard let поля = (try? JSONSerialization.jsonObject(with: данные)) as? [String: Any] else {
            return (код == 401 || код == 403) ? .нуженВход : .отказ(ПоискСайтаText.т("ps_fail"))
        }
        let запросФото = строка(поля["query"])
        if да(поля["ok"]) && !запросФото.isEmpty {
            return .найдено(запрос: запросФото, раздел: строка(поля["category"]))
        }
        if строка(поля["need"]) == "auth" || строка(поля["error"]) == "auth" { return .нуженВход }
        let ошибка = строка(поля["error"])
        /* Машинный код («rate_limit») — не человеку: как ulxErr сайта, показываем общий текст. */
        if ошибка.isEmpty || ошибка.range(of: "^[a-z][a-z0-9_]{1,14}$", options: .regularExpression) != nil {
            return .отказ(ПоискСайтаText.т("ps_fail"))
        }
        return .отказ(ошибка)
    }

    private static func строка(_ значение: Any?) -> String {
        if let s = значение as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let n = значение as? NSNumber { return n.stringValue }
        return ""
    }

    private static func да(_ значение: Any?) -> Bool {
        if let b = значение as? Bool { return b }
        if let n = значение as? NSNumber { return n.intValue != 0 }
        if let s = значение as? String { return s == "1" || s == "true" }
        return false
    }
}

/// Итог распознавания для ленты: запрос в поле и раздел (пусто — без раздела).
struct ИтогПоискаПоФото: Equatable {
    let id = UUID()
    let запрос: String
    let раздел: String
}

@MainActor
final class ПоискПоФотоСайта: ObservableObject {
    static let shared = ПоискПоФотоСайта()

    enum Шаг: Equatable {
        case камера
        case идёт
        case ошибка(String)
        case вход
        case формаВхода
    }

    /// Выбор «Снять» / «Выбрать из фото».
    @Published var выбор = false
    /// Системная галерея (PhotosPicker).
    @Published var галерея = false
    @Published var элемент: PhotosPickerItem? = nil
    /// Окно поверх всего: камера, «Распознаём фото…», ошибка, вход.
    @Published var окно = false
    @Published private(set) var шаг: Шаг = .идёт
    @Published private(set) var превью: UIImage? = nil
    /// Распознали — лента подставляет запрос и раздел.
    @Published private(set) var итог: ИтогПоискаПоФото? = nil
    /// Плашка «Ищем: …» (toast сайта).
    @Published private(set) var плашка: String? = nil

    private var задача: Task<Void, Never>? = nil
    private var поколение = 0

    private init() {}

    static var естьКамера: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    private func т(_ ключ: String) -> String { ПоискСайтаText.т(ключ) }

    /// Камера в поле поиска (mkPhotoSearch): гость — окно входа, иначе выбор источника.
    func начать() {
        Task { @MainActor in
            let состояние = await SiteSession.состояние()
            if состояние.вошёл == false {
                показатьВход()
            } else {
                предложить()
            }
        }
    }

    /// «Снять» или «Выбрать из фото»; камеры нет — сразу галерея (у сайта без getUserMedia — окно с «Загрузить фото»).
    func предложить() {
        if Self.естьКамера {
            выбор = true
        } else {
            галерея = true
        }
    }

    func снять() {
        Task { @MainActor in
            /* Лист выбора ещё уходит с экрана — окно камеры поверх него iOS не покажет. */
            try? await Task.sleep(nanoseconds: 350_000_000)
            шаг = .камера
            превью = nil
            окно = true
        }
    }

    func выбратьИзФото() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            галерея = true
        }
    }

    /// Снимок с камеры.
    func снято(_ снимок: UIImage) {
        обработать(снимок)
    }

    /// Камеру закрыли «Отменить» — окно уходит; сняли — окно уже показывает распознавание.
    func камераЗакрыта() {
        if шаг == .камера { окно = false }
    }

    /// Выбрали в галерее.
    func принять(_ выбранный: PhotosPickerItem?) {
        guard let выбранный else { return }
        элемент = nil
        поколение += 1
        let номер = поколение
        Task { @MainActor in
            let данные = try? await выбранный.loadTransferable(type: Data.self)
            guard номер == поколение else { return }
            /* Галерея ещё закрывается — окно поверх неё покажем чуть позже. */
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard номер == поколение else { return }
            guard let данные, let снимок = UIImage(data: данные) else {
                показатьОшибку(т("ps_bad_img"))
                return
            }
            обработать(снимок)
        }
    }

    private func обработать(_ снимок: UIImage) {
        превью = снимок
        шаг = .идёт
        окно = true
        поколение += 1
        let номер = поколение
        задача?.cancel()
        guard let адрес = ПоискПоФотоAPI.сжать(снимок) else {
            показатьОшибку(т("ps_fail"))
            return
        }
        задача = Task { @MainActor in
            let ответ = await ПоискПоФотоAPI.отправить(адрес)
            guard номер == поколение, !Task.isCancelled else { return }
            switch ответ {
            case .найдено(let запрос, let раздел):
                окно = false
                итог = ИтогПоискаПоФото(запрос: запрос, раздел: раздел)
                показатьПлашку(String(format: т("ps_found"), запрос))
            case .нуженВход:
                шаг = .вход
            case .отказ(let текст):
                шаг = .ошибка(текст)
            case .сеть:
                шаг = .ошибка(т("err_no_conn"))
            }
        }
    }

    private func показатьОшибку(_ текст: String) {
        шаг = .ошибка(текст)
        окно = true
    }

    private func показатьВход() {
        шаг = .вход
        превью = nil
        окно = true
    }

    /// «Уже есть аккаунт — войти»: форма входа в том же окне (или страница кабинета, если свой вход выключен).
    func войти() {
        if Config.нативныйВход {
            шаг = .формаВхода
        } else {
            закрыть()
            if let адрес = Config.страницаСайта("cabinet.php") { WebBridge.shared.pendingURL = адрес }
        }
    }

    /// Вошли — «…и продолжить»: снова выбор источника фото.
    func вошли() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            предложить()
        }
    }

    /// «Другое фото» в окне ошибки — _mkPhotoError сайта снова открывает выбор файла.
    func другоеФото() {
        закрыть()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            предложить()
        }
    }

    func закрыть() {
        поколение += 1
        задача?.cancel()
        задача = nil
        окно = false
    }

    private func показатьПлашку(_ текст: String) {
        плашка = текст
        UIAccessibility.post(notification: .announcement, argument: текст)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            if self.плашка == текст { self.плашка = nil }
        }
    }
}

// MARK: - Виды

/// Выбор источника, галерея и окно поиска по фото — слой под лентой, чтобы его листы не спорили с листами ленты.
struct СлойПоискаПоФото: View {
    @ObservedObject var модель: ПоискПоФотоСайта
    let открыть: (URL) -> Void

    private func т(_ ключ: String) -> String { ПоискСайтаText.т(ключ) }

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .confirmationDialog(т("ps_title"), isPresented: $модель.выбор, titleVisibility: .visible) {
                Button(т("shoot")) { модель.снять() }
                Button(т("pick")) { модель.выбратьИзФото() }
                Button(т("cancel"), role: .cancel) {}
            } message: {
                Text(т("ps_hint"))
            }
            .photosPicker(isPresented: $модель.галерея, selection: $модель.элемент, matching: .images)
            .onChange(of: модель.элемент) { _, новый in
                модель.принять(новый)
            }
            .fullScreenCover(isPresented: $модель.окно) {
                ОкноПоискаПоФото(модель: модель, открыть: открыть)
            }
    }
}

/// Окно поверх всего: камера, «Распознаём фото…», ошибка или вход — .mk-psheet сайта на затемнении.
struct ОкноПоискаПоФото: View {
    @ObservedObject var модель: ПоискПоФотоСайта
    let открыть: (URL) -> Void

    private func т(_ ключ: String) -> String { ПоискСайтаText.т(ключ) }

    var body: some View {
        Group {
            switch модель.шаг {
            case .камера:
                КамераПодачи(снято: { снимок in модель.снято(снимок) }, закрыть: { модель.камераЗакрыта() })
                    .ignoresSafeArea()
            case .формаВхода:
                ЭкранВхода(eGovВключён: true, открыть: { адрес in
                    модель.закрыть()
                    открыть(адрес)
                }, вошли: {
                    модель.вошли()
                })
            default:
                затемнение
            }
        }
        .presentationBackground(фон)
    }

    private var фон: Color {
        switch модель.шаг {
        case .камера: return Color.black
        case .формаВхода: return Theme.фонСтраницы
        default: return Color.clear
        }
    }

    /// Затемнение rgba(15,23,42,.55) и карточка по центру; нажатие мимо карточки закрывает, как у сайта.
    private var затемнение: some View {
        ZStack {
            Color(red: 15 / 255, green: 23 / 255, blue: 42 / 255).opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { модель.закрыть() }
                .accessibilityHidden(true)
            КарточкаПоискаПоФото(модель: модель, открыть: открыть)
                .padding(20)
        }
    }
}

/// .mk-psheet: белая карточка до 380 pt, скругление 20, отступы 24, текст по центру.
private struct КарточкаПоискаПоФото: View {
    @ObservedObject var модель: ПоискПоФотоСайта
    let открыть: (URL) -> Void

    private func т(_ ключ: String) -> String { ПоискСайтаText.т(ключ) }

    var body: some View {
        VStack(spacing: 0) {
            switch модель.шаг {
            case .ошибка(let текст):
                ошибка(текст)
            case .вход:
                вход
            default:
                ИдётРаспознавание(превью: модель.превью)
            }
        }
        .padding(24)
        .frame(maxWidth: 380)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.xl, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if модель.шаг != .идёт {
                Button { модель.закрыть() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.текстВторой)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(6)
                .accessibilityLabel(т("close"))
            }
        }
        .shadow(color: Color(red: 15 / 255, green: 23 / 255, blue: 42 / 255).opacity(0.4), radius: 30, x: 0, y: 24)
    }

    /// _mkPhotoError: красный значок, текст ошибки, «Попробуйте фото чётче…», «Другое фото».
    private func ошибка(_ текст: String) -> some View {
        VStack(spacing: 0) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Theme.ценаСкидка)
                .frame(width: 66, height: 66)
                .background(Theme.скидкаФон, in: RoundedRectangle(cornerRadius: Theme.Радиус.xl, style: .continuous))
                .padding(.bottom, 16)
                .accessibilityHidden(true)
            Text(текст)
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)
            Text(т("ps_retry_hint"))
                .font(.system(size: 13))
                .foregroundStyle(Theme.текстВторой)
                .multilineTextAlignment(.center)
                .padding(.bottom, 20)
            КнопкаЛистаФото(заголовок: т("ps_retry"), значок: "square.and.arrow.up") { модель.другоеФото() }
        }
    }

    /// mkRegGate: «Нужен аккаунт», «Зарегистрируйтесь, чтобы искать по фото», eGov, «Уже есть аккаунт — войти».
    private var вход: some View {
        VStack(spacing: 0) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Theme.зелёный)
                .frame(width: 66, height: 66)
                .background(Theme.мята, in: RoundedRectangle(cornerRadius: Theme.Радиус.xl, style: .continuous))
                .padding(.bottom, 16)
                .accessibilityHidden(true)
            Text(т("gate_account_title"))
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)
            Text(т("reg_photo_search"))
                .font(.system(size: 14))
                .foregroundStyle(Theme.текстВторой)
                .multilineTextAlignment(.center)
                .padding(.bottom, 20)
            КнопкаЛистаФото(заголовок: т("gate_go"), значок: "checkmark.shield") {
                модель.закрыть()
                if let адрес = Config.страницаСайта("cabinet?egov=1") { открыть(адрес) }
            }
            .padding(.bottom, 10)
            Button { модель.войти() } label: {
                Text(т("reg_have_account"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.зелёный2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button { модель.закрыть() } label: {
                Text(т("later"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// .mk-psheet-up: зелёная кнопка во всю ширину, 15 pt жирным, скругление 12.
private struct КнопкаЛистаФото: View {
    let заголовок: String
    let значок: String
    let действие: () -> Void

    var body: some View {
        Button(action: действие) {
            HStack(spacing: 10) {
                Image(systemName: значок)
                    .font(.system(size: 17, weight: .semibold))
                Text(заголовок)
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .padding(14)
            .background(Theme.зелёный, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// _mkPhotoProgress: превью 192 × 192 с бегущей полосой и уголками, «Распознаём фото…», полоса загрузки.
private struct ИдётРаспознавание: View {
    let превью: UIImage?
    @State private var бег = false

    init(превью: UIImage?) {
        self.превью = превью
    }

    private func т(_ ключ: String) -> String { ПоискСайтаText.т(ключ) }

    var body: some View {
        VStack(spacing: 0) {
            картинка
                .padding(.top, 2)
                .padding(.bottom, 20)
            Text(т("ps_recognizing"))
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .multilineTextAlignment(.center)
                .padding(.bottom, 6)
            Text(т("ps_recognizing_sub"))
                .font(.system(size: 13))
                .foregroundStyle(Theme.текстВторой)
                .multilineTextAlignment(.center)
                .padding(.bottom, 16)
            полоса
        }
        .onAppear { бег = true }
        .accessibilityElement(children: .combine)
    }

    private var картинка: some View {
        ZStack {
            if let превью {
                Image(uiImage: превью)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(colors: [Theme.мята, Theme.поверхность2], startPoint: .topLeading,
                               endPoint: .bottomTrailing)
            }
            LinearGradient(stops: [Gradient.Stop(color: Color(red: 29 / 255, green: 158 / 255, blue: 94 / 255).opacity(0), location: 0),
                                   Gradient.Stop(color: Color(red: 29 / 255, green: 158 / 255, blue: 94 / 255).opacity(0.45), location: 0.25),
                                   Gradient.Stop(color: Color.white.opacity(0.5), location: 0.5),
                                   Gradient.Stop(color: Color(red: 29 / 255, green: 158 / 255, blue: 94 / 255).opacity(0.45), location: 0.75),
                                   Gradient.Stop(color: Color(red: 29 / 255, green: 158 / 255, blue: 94 / 255).opacity(0), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 56)
                .frame(maxHeight: .infinity, alignment: .top)
                .offset(y: бег ? 192 : -56)
                .animation(ДвижениеСайта.мягко(.easeInOut(duration: 1.6).repeatForever(autoreverses: false)), value: бег)
            УголкиРамки()
                .padding(10)
                .opacity(бег ? 0.65 : 1)
                .animation(ДвижениеСайта.мягко(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)), value: бег)
        }
        .frame(width: 192, height: 192)
        .background(Theme.поверхность2)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    /// .mk-pprog-bar: 6 pt, бегущий отрезок 40 % ширины от ярко-зелёного к зелёному.
    private var полоса: some View {
        GeometryReader { место in
            Capsule()
                .fill(LinearGradient(colors: [Theme.зелёныйЯркий, Theme.зелёный2], startPoint: .leading,
                                     endPoint: .trailing))
                .frame(width: место.size.width * 0.4)
                .offset(x: бег ? место.size.width : -место.size.width * 0.4)
                .animation(ДвижениеСайта.мягко(.easeInOut(duration: 1.15).repeatForever(autoreverses: false)), value: бег)
        }
        .frame(height: 6)
        .background(Theme.поверхность2)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}

/// Четыре белых уголка 24 × 24 рамки распознавания (.mk-pc).
private struct УголкиРамки: View {
    var body: some View {
        Canvas { контекст, размер in
            let д: CGFloat = 24
            let р: CGFloat = 6
            var путь = Path()
            /* левый верхний */
            путь.move(to: CGPoint(x: 0, y: д))
            путь.addLine(to: CGPoint(x: 0, y: р))
            путь.addQuadCurve(to: CGPoint(x: р, y: 0), control: CGPoint(x: 0, y: 0))
            путь.addLine(to: CGPoint(x: д, y: 0))
            /* правый верхний */
            путь.move(to: CGPoint(x: размер.width - д, y: 0))
            путь.addLine(to: CGPoint(x: размер.width - р, y: 0))
            путь.addQuadCurve(to: CGPoint(x: размер.width, y: р), control: CGPoint(x: размер.width, y: 0))
            путь.addLine(to: CGPoint(x: размер.width, y: д))
            /* левый нижний */
            путь.move(to: CGPoint(x: 0, y: размер.height - д))
            путь.addLine(to: CGPoint(x: 0, y: размер.height - р))
            путь.addQuadCurve(to: CGPoint(x: р, y: размер.height), control: CGPoint(x: 0, y: размер.height))
            путь.addLine(to: CGPoint(x: д, y: размер.height))
            /* правый нижний */
            путь.move(to: CGPoint(x: размер.width - д, y: размер.height))
            путь.addLine(to: CGPoint(x: размер.width - р, y: размер.height))
            путь.addQuadCurve(to: CGPoint(x: размер.width, y: размер.height - р),
                              control: CGPoint(x: размер.width, y: размер.height))
            путь.addLine(to: CGPoint(x: размер.width, y: размер.height - д))
            контекст.stroke(путь, with: .color(Color.white.opacity(0.92)),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
        .shadow(color: Color.black.opacity(0.4), radius: 1)
    }
}
