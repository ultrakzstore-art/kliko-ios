import SwiftUI
import PhotosUI
import UIKit

/**
 ПОИСК ПО ФОТО — СВОЙ ЭКРАН КАМЕРЫ (владелец 29.09.2026: «И поиск по фото тоже дизайн камеры»).

 Запрос к сайту прежний — тот же, что mkPhotoSearch сайта (js/marketplace.min.js), см. ПоискПоФотоAPI ниже:
 • снимок — как _mkPhotoPicked: большая сторона не больше 1024, JPEG 0,82, dataURL;
 • POST /api/photo_search.php, multipart, поле imgb64 (и csrf страницы), с куками веб-сессии (SiteSession);
 • ответ ok + query (+ category) — что распознано; need/error «auth» — нужен вход. Области снимка (обрезки) API не
   принимает — только весь кадр, поэтому своей рамки-обрезки нет: рамка на камере — подсказка, куда навести.

 Что видит человек (PhotoSearchCamera.swift, PhotoSearchResults.swift):
 • гость (сеанс сайта «не вошёл») — до камеры нативный лист «Войдите, чтобы искать по фото»: «Войти» (ВходПоверх),
   «Регистрация через eGov», «Позже»; вошёл — сразу камера;
 • тёмный экран живой камеры (AVFoundation): ✕, фонарик, большой затвор, галерея с миниатюрой последнего фото,
   подсказка «Наведите на вещь…», рамка с уголками (без движения при «Уменьшении движения»); камеры нет или доступ
   запрещён — заглушка с «Выбрать из галереи» (и «Открыть Настройки»), без камеры галерея открывается сама;
 • снимок — «Ищем похожие…» (Kliko AI) поверх фото; затем сетка карточек ленты (ListingCard) «Похожие на ваше фото»
   по распознанному запросу и разделу (api/listings.php, как лента; в разделе пусто — без раздела), «Снять ещё» и
   «Все в ленте» (прежнее поведение: запрос встаёт в поле ленты, плашка «Ищем: …»);
 • ошибка распознавания или сети — «Повторить», «Снять ещё», «Выбрать из галереи»; сайт просит вход — лист входа;
 • над затвором — режим «Навести камеру» / «Выбрать фото» (последний запоминается): «Навести камеру» — живой поиск,
   стабильный кадр сам уходит в этот же запрос, похожие — полосой снизу (PhotoSearchLive.swift).
 */
enum ПоискПоФотоAPI {
    enum Итог: Equatable {
        case найдено(запрос: String, раздел: String)
        case нуженВход
        case отказ(String)
        /// «Свой ИИ»: own_ai:"<код>", готовый текст в error — окно с «Настройки своего ИИ».
        case свойИИ(ОтказСвоегоИИ)
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
        /* Origin не подставляем (владелец: без поддельных Origin/Referer): photo_search.php источник не проверяет —
           ему нужны вошедшая сессия (куки) и токен страницы в теле. */
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
        if let отказ = ОтказСвоегоИИ.из(поля) { return .свойИИ(отказ) }
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
        case результаты
        case ошибка(String)
    }

    /// Гостю — лист «Войдите, чтобы искать по фото» до камеры.
    @Published var ворота = false
    /// Экран поиска по фото поверх всего: камера, «Ищем похожие…», похожие, ошибка.
    @Published var окно = false
    /// Системная галерея (PhotosPicker) — из экрана камеры.
    @Published var галерея = false
    @Published var элемент: PhotosPickerItem? = nil
    @Published private(set) var шаг: Шаг = .камера
    @Published private(set) var превью: UIImage? = nil
    /// Последний снимок этой камеры — миниатюра у кнопки галереи, если доступа к фото нет.
    @Published private(set) var последний: UIImage? = nil
    /// Что распознал Kliko AI и в каком разделе искали.
    @Published private(set) var запрос = ""
    @Published private(set) var раздел = ""
    @Published private(set) var товары: [Listing] = []
    @Published private(set) var всего: Int? = nil
    /// «Все в ленте» — лента подставляет запрос и раздел.
    @Published private(set) var итог: ИтогПоискаПоФото? = nil
    /// Плашка «Ищем: …» (toast сайта).
    @Published private(set) var плашка: String? = nil

    private var адресФото: String? = nil
    private var задача: Task<Void, Never>? = nil
    private var поколение = 0

    private init() {}

    private func т(_ ключ: String) -> String { ПоискСайтаText.т(ключ) }

    /// Камера в поле поиска: гость — лист входа, иначе сразу камера.
    func начать() {
        Task { @MainActor in
            let состояние = await SiteSession.состояние()
            if состояние.вошёл == false {
                ворота = true
            } else {
                открытьКамеру()
            }
        }
    }

    func открытьКамеру() {
        сбросить()
        шаг = .камера
        окно = true
    }

    /// «Снять ещё» — обратно к камере в том же окне.
    func снятьЕщё() {
        сбросить()
        шаг = .камера
    }

    /// «Выбрать из галереи» с экрана ошибки или заглушки.
    func открытьГалерею() {
        галерея = true
    }

    private func сбросить() {
        поколение += 1
        задача?.cancel()
        задача = nil
        превью = nil
        адресФото = nil
        запрос = ""
        раздел = ""
        товары = []
        всего = nil
    }

    /// Снимок с камеры.
    func снято(_ снимок: UIImage) {
        последний = снимок
        обработать(снимок)
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
            guard let данные, let снимок = UIImage(data: данные) else {
                шаг = .ошибка(т("ps_bad_img"))
                return
            }
            обработать(снимок)
        }
    }

    private func обработать(_ снимок: UIImage) {
        сбросить()
        превью = снимок
        шаг = .идёт
        guard let адрес = ПоискПоФотоAPI.сжать(снимок) else {
            шаг = .ошибка(т("ps_fail"))
            return
        }
        адресФото = адрес
        распознать(адрес)
    }

    /// Фото — на сайт (тот же запрос, что mkPhotoSearch), распознанное — в выдачу похожих.
    private func распознать(_ адрес: String) {
        let номер = поколение
        шаг = .идёт
        задача?.cancel()
        задача = Task { @MainActor in
            let ответ = await ПоискПоФотоAPI.отправить(адрес)
            guard номер == поколение, !Task.isCancelled else { return }
            switch ответ {
            case .найдено(let найдено, let ключ):
                запрос = найдено
                раздел = ключ
                await найтиПохожие(номер)
            case .нуженВход:
                закрыть()
                try? await Task.sleep(nanoseconds: 450_000_000)
                ворота = true
            case .отказ(let текст):
                шаг = .ошибка(текст)
            case .свойИИ(let отказ):
                шаг = .ошибка(отказ.текст)
                ОкноСвоегоИИ.показатьОтказ(отказ)
            case .сеть:
                шаг = .ошибка(т("err_no_conn"))
            }
        }
    }

    /// Объявления по распознанному запросу — как лента (api/listings.php); в разделе пусто — ещё раз без раздела.
    private func найтиПохожие(_ номер: Int) async {
        var з = ListingsAPI.Запрос()
        з.q = запрос
        з.cat = раздел
        do {
            var страница = try await ListingsAPI.загрузить(з).страница
            guard номер == поколение, !Task.isCancelled else { return }
            if страница.items.isEmpty && !з.cat.isEmpty {
                з.cat = ""
                let шире = try await ListingsAPI.загрузить(з).страница
                guard номер == поколение, !Task.isCancelled else { return }
                if !шире.items.isEmpty {
                    раздел = ""
                    страница = шире
                }
            }
            /* ТОП, которых меньше, чем ТОП-мест, сервер ставит по кругу (rank_gold_layout), и одно объявление приходит
               дважды — два одинаковых id в ForEach сетки похожих ломают её; оставляем первое. */
            var были = Set<String>()
            товары = страница.items.filter { были.insert($0.id).inserted }
            всего = страница.total
            шаг = .результаты
            let объявление = товары.isEmpty ? т("ps_empty") : String(format: т("ps_count"), всего ?? товары.count)
            UIAccessibility.post(notification: .announcement, argument: объявление)
        } catch {
            guard номер == поколение, !Task.isCancelled else { return }
            шаг = .ошибка(т("err_no_conn"))
        }
    }

    /// «Повторить»: распознано — снова выдача, нет — снова то же фото на сайт; фото нет — к камере.
    func повторить() {
        if !запрос.isEmpty {
            поколение += 1
            let номер = поколение
            шаг = .идёт
            задача?.cancel()
            задача = Task { @MainActor in await найтиПохожие(номер) }
        } else if let адрес = адресФото {
            поколение += 1
            распознать(адрес)
        } else {
            снятьЕщё()
        }
    }

    /// «Все в ленте»: окно закрывается, запрос встаёт в поле ленты, раздел выбирается, плашка «Ищем: …».
    func вЛенту() {
        guard !запрос.isEmpty else { return }
        let найдено = запрос
        let ключ = раздел
        закрыть()
        итог = ИтогПоискаПоФото(запрос: найдено, раздел: ключ)
        показатьПлашку(String(format: т("ps_found"), найдено))
    }

    /// «Войти» в листе гостя: свой экран входа поверх всего; вошли — камера.
    func войтиИзВорот() {
        ворота = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            ВходПоверх.показать(готово: { [weak self] in
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    self?.открытьКамеру()
                }
            })
        }
    }

    /// «Регистрация через eGov» в листе гостя.
    func eGovИзВорот(_ открыть: @escaping (URL) -> Void) {
        ворота = false
        guard let адрес = Config.страницаСайта("cabinet?egov=1") else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            открыть(адрес)
        }
    }

    func закрыть() {
        поколение += 1
        задача?.cancel()
        задача = nil
        окно = false
    }

    /// Живой поиск камерой услышал от сайта «нужен вход» (сеанс истёк, пока окно открыто): как у снимка — окно
    /// закрывается, через миг лист входа.
    func входДляЖивого() {
        закрыть()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            ворота = true
        }
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

// MARK: - Слой и окно

/// Лист гостя и окно поиска по фото — слой под лентой, чтобы его листы не спорили с листами ленты.
struct СлойПоискаПоФото: View {
    @ObservedObject var модель: ПоискПоФотоСайта
    let открыть: (URL) -> Void

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .sheet(isPresented: $модель.ворота) {
                ЛистВходаПоискаФото(модель: модель, открыть: открыть)
            }
            .fullScreenCover(isPresented: $модель.окно) {
                ОкноПоискаПоФото(модель: модель, открыть: открыть)
            }
    }
}

/// Окно поверх всего: камера → «Ищем похожие…» → похожие (карточки открываются в том же стеке) или ошибка.
struct ОкноПоискаПоФото: View {
    @ObservedObject var модель: ПоискПоФотоСайта
    let открыть: (URL) -> Void
    /// Камера живёт, пока открыто окно: «Снять ещё» не собирает её заново.
    @StateObject private var камера = КамераПоиска()
    /// Живой поиск («Навести камеру») — тоже на всё окно: вернулись от объявления — полоса похожих на месте.
    @StateObject private var живой = ЖивойПоискКамеры()
    /// Стек окна: объявление открыто (из сетки похожих или из полосы живого поиска) — оно в оформлении телефона,
    /// а не в тёмном камеры.
    @State private var путь = NavigationPath()

    var body: some View {
        NavigationStack(path: $путь) {
            содержимое
                .navigationDestination(for: Listing.self) { товар in
                    ListingDetailView(товар: товар, открыть: { адрес in
                        модель.закрыть()
                        открыть(адрес)
                    })
                }
        }
        .tint(Theme.зелёный2)
        .preferredColorScheme(модель.шаг == .результаты || !путь.isEmpty ? nil : .dark)
        .photosPicker(isPresented: $модель.галерея, selection: $модель.элемент, matching: .images)
        .onChange(of: модель.элемент) { _, новый in
            модель.принять(новый)
        }
        .onDisappear {
            живой.приостановить()
            камера.остановить()
        }
    }

    @ViewBuilder
    private var содержимое: some View {
        switch модель.шаг {
        case .камера:
            ЭкранКамерыПоиска(модель: модель, камера: камера, живой: живой)
                .toolbar(.hidden, for: .navigationBar)
        case .идёт:
            ЭкранРаспознаванияФото(модель: модель)
                .toolbar(.hidden, for: .navigationBar)
        case .результаты:
            ЭкранПохожихПоФото(модель: модель)
        case .ошибка(let текст):
            ЭкранОшибкиПоискаФото(модель: модель, текст: текст)
                .toolbar(.hidden, for: .navigationBar)
        }
    }
}

/// Лист гостя до камеры (mkRegGate сайта, нативно): зачем вход, «Войти», «Регистрация через eGov», «Позже».
private struct ЛистВходаПоискаФото: View {
    @ObservedObject var модель: ПоискПоФотоСайта
    let открыть: (URL) -> Void

    private func т(_ ключ: String) -> String { ПоискСайтаText.т(ключ) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Theme.зелёный2)
                    .frame(width: 72, height: 72)
                    .background(Theme.мята, in: Circle())
                    .padding(.bottom, 16)
                    .accessibilityHidden(true)
                Text(т("ps_gate_title"))
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(Theme.текст)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 8)
                Text(т("ps_gate_text"))
                    .font(.subheadline)
                    .foregroundStyle(Theme.текстВторой)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 22)
                ЗелёнаяКнопкаФото(заголовок: т("sign_in"), значок: "person.crop.circle") { модель.войтиИзВорот() }
                    .padding(.bottom, 10)
                ЗелёнаяКнопкаФото(заголовок: т("gate_go"), значок: "checkmark.shield", контурная: true) {
                    модель.eGovИзВорот(открыть)
                }
                .padding(.bottom, 6)
                Button { модель.ворота = false } label: {
                    Text(т("later"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.текстВторой)
                        .frame(minHeight: 44)
                        .padding(.horizontal, 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 16)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.поверхность.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// Кнопка во всю ширину, как у экранов подачи: зелёная заливка или зелёный контур, скругление 14, Dynamic Type.
struct ЗелёнаяКнопкаФото: View {
    let заголовок: String
    let значок: String
    var контурная = false
    var наТёмном = false
    let действие: () -> Void

    init(заголовок: String, значок: String, контурная: Bool = false, наТёмном: Bool = false,
         действие: @escaping () -> Void) {
        self.заголовок = заголовок
        self.значок = значок
        self.контурная = контурная
        self.наТёмном = наТёмном
        self.действие = действие
    }

    private var цветТекста: Color {
        if !контурная { return Color.white }
        return наТёмном ? Color.white : Theme.зелёный2
    }

    var body: some View {
        Button(action: действие) {
            HStack(spacing: 10) {
                Image(systemName: значок)
                    .font(.body.weight(.semibold))
                    .accessibilityHidden(true)
                Text(заголовок)
                    .font(.body.weight(.bold))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(цветТекста)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, 16)
            .background {
                RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                    .fill(контурная ? AnyShapeStyle(Color.clear) : AnyShapeStyle(Theme.зелёный2))
            }
            .overlay {
                if контурная {
                    RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                        .strokeBorder(наТёмном ? Color.white.opacity(0.55) : Theme.зелёный2, lineWidth: 1.5)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        }
        .buttonStyle(НажатиеКнопкиФото())
    }
}

/// Лёгкое сжатие под пальцем (как .mh-c:active сайта) — остаётся и при «Уменьшении движения».
struct НажатиеКнопкиФото: ButtonStyle {
    var сжатие: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? сжатие : 1)
            .animation(ДвижениеСайта.нажатие, value: configuration.isPressed)
    }
}

/// Четыре уголка рамки распознавания (.mk-pc сайта): длина, цвет и толщина — для камеры и превью.
struct УголкиПоискаФото: View {
    var длина: CGFloat = 24
    var цвет: Color = Color.white.opacity(0.92)
    var толщина: CGFloat = 2.5

    var body: some View {
        Canvas { контекст, размер in
            let д = длина
            let р: CGFloat = min(10, длина / 3)
            let ш = размер.width
            let в = размер.height
            var путь = Path()
            /* левый верхний */
            путь.move(to: CGPoint(x: 0, y: д))
            путь.addLine(to: CGPoint(x: 0, y: р))
            путь.addQuadCurve(to: CGPoint(x: р, y: 0), control: CGPoint(x: 0, y: 0))
            путь.addLine(to: CGPoint(x: д, y: 0))
            /* правый верхний */
            путь.move(to: CGPoint(x: ш - д, y: 0))
            путь.addLine(to: CGPoint(x: ш - р, y: 0))
            путь.addQuadCurve(to: CGPoint(x: ш, y: р), control: CGPoint(x: ш, y: 0))
            путь.addLine(to: CGPoint(x: ш, y: д))
            /* левый нижний */
            путь.move(to: CGPoint(x: 0, y: в - д))
            путь.addLine(to: CGPoint(x: 0, y: в - р))
            путь.addQuadCurve(to: CGPoint(x: р, y: в), control: CGPoint(x: 0, y: в))
            путь.addLine(to: CGPoint(x: д, y: в))
            /* правый нижний */
            путь.move(to: CGPoint(x: ш - д, y: в))
            путь.addLine(to: CGPoint(x: ш - р, y: в))
            путь.addQuadCurve(to: CGPoint(x: ш, y: в - р), control: CGPoint(x: ш, y: в))
            путь.addLine(to: CGPoint(x: ш, y: в - д))
            контекст.stroke(путь, with: .color(цвет),
                            style: StrokeStyle(lineWidth: толщина, lineCap: .round, lineJoin: .round))
        }
        .shadow(color: Color.black.opacity(0.35), radius: 2)
        .accessibilityHidden(true)
    }
}
