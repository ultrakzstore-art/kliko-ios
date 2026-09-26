import SwiftUI
import UIKit
import WebKit

/**
 ОБЩЕЕ ДЛЯ НОВЫХ РАЗДЕЛОВ КАБИНЕТА (CabinetPlus): вызовы с текстом ошибки для человека, номер вошедшего, плашка.
 Транспорт — тот же, что у всего кабинета (МоиОбъявленияAPI → КабинетСайта: fetch изнутри страницы сайта под слоем,
 её куки и токен CSRF). Ошибки — как ulxErr сайта: короткий латинский код не показываем, показываем текст сервера.
 */
@MainActor
enum ЗапросыКабинета {
    typealias A = МоиОбъявленияAPI

    struct Сбой: Error {
        let текст: String
        var нуженВход = false
        var нуженПРО = false
    }

    /// Ответ → словарь или Сбой.
    static func проверить(_ j: [String: Any]?) throws -> [String: Any] {
        guard let j else { throw Сбой(текст: КабинетПлюсText.т("err_generic")) }
        if A.нетСессии(j) { throw Сбой(текст: CabinetText.т("signed_out"), нуженВход: true) }
        guard A.да(j["ok"]) else { throw Сбой(текст: текстОшибки(j), нуженПРО: A.да(j["need_pro"]) || A.да(j["need_tier"])) }
        return j
    }

    /// Текст отказа для человека: error / message / msg сервера или «Ошибка».
    static func текстОшибки(_ j: [String: Any]) -> String {
        for ключ in ["message", "msg", "error"] {
            let т = A.строка(j[ключ]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !т.isEmpty && !КабинетСайта.машинныйКод(т) { return т }
        }
        if A.да(j["need_pro"]) || A.да(j["need_tier"]) { return БизнесРазделыText.т("pro_need") }
        return КабинетПлюсText.т("err_generic")
    }

    static func получить(_ хвост: String, отКорня: Bool = false) async throws -> [String: Any] {
        let сырой: [String: Any]?
        do {
            сырой = try await A.получить(хвост, отКорня: отКорня)
        } catch {
            throw Сбой(текст: КабинетПлюсText.т("no_conn"))
        }
        return try проверить(сырой)
    }

    static func отправить(_ хвост: String, _ тело: [String: Any], отКорня: Bool = false) async throws -> [String: Any] {
        let сырой: [String: Any]
        do {
            сырой = try await A.отправить(хвост, тело: тело, отКорня: отКорня)
        } catch {
            throw Сбой(текст: КабинетПлюсText.т("no_conn"))
        }
        return try проверить(сырой)
    }

    /// Сбой → текст для плашки.
    static func текст(_ ошибка: Error) -> String {
        (ошибка as? Сбой)?.текст ?? КабинетПлюсText.т("no_conn")
    }

    /// Номер вошедшего (CAB_USER.id / KlikoUser.id, запасной — ulx_me_id): me_id аренд и обменов.
    static func мойНомер() async -> String {
        if let известный = await SiteSession.состояние().пользователь, !известный.isEmpty { return известный }
        return (try? await КабинетСайта.состояние())?.uid ?? ""
    }

    /// Адрес картинки сайта: абсолютный как есть, «/img/…» — от корня.
    static func картинка(_ путь: String) -> URL? {
        let п = путь.trimmingCharacters(in: .whitespaces)
        if п.isEmpty { return nil }
        return Config.url(п.hasPrefix("/") || п.hasPrefix("http") ? п : "/" + п)
    }

    /// «12 345» — toLocaleString("ru-RU").
    static func деньги(_ n: Double) -> String { СделкиФормат.деньги(Int(n.rounded())) }
}

/// Плашка внизу экрана (toast сайта) с автоскрытием — для экранов этого модуля.
@MainActor
final class ПлашкаРаздела: ObservableObject {
    @Published var текст: String? = nil
    private var задача: Task<Void, Never>? = nil

    func показать(_ новый: String) {
        let чистый = новый.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !чистый.isEmpty else { return }
        withAnimation(.easeOut(duration: 0.2)) { текст = чистый }
        UIAccessibility.post(notification: .announcement, argument: чистый)
        задача?.cancel()
        задача = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.2)) { self?.текст = nil }
        }
    }
}

/// Переключатель вкладок сайта (.dlv-tab, rent-tab): две-три кнопки-капсулы.
struct ВкладкиРаздела: View {
    let варианты: [(ключ: String, подпись: String)]
    @Binding var выбрано: String

    var body: some View {
        HStack(spacing: 6) {
            ForEach(варианты, id: \.ключ) { вариант in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { выбрано = вариант.ключ }
                } label: {
                    Text(вариант.подпись)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(выбрано == вариант.ключ ? Color.white : Theme.текст)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(выбрано == вариант.ключ ? Theme.акцент : Theme.поверхность2,
                                    in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(выбрано == вариант.ключ ? .isSelected : [])
            }
        }
    }
}

/// Кнопка действия в карточке: главная (зелёная), тревожная (красная подложка), предупреждение (жёлтая), обычная.
struct КнопкаРаздела: View {
    enum Вид { case главная, плохо, внимание, обычная }

    let подпись: String
    var значок: String? = nil
    var вид: Вид = .обычная
    var занято = false
    let действие: () -> Void

    private var текст: Color {
        switch вид {
        case .главная: return Color.white
        case .плохо: return КраскаОбъявлений.плохоТекст
        case .внимание: return КраскаОбъявлений.предупреждениеТекст
        case .обычная: return Theme.акцент
        }
    }

    private var фон: Color {
        switch вид {
        case .главная: return Theme.акцент
        case .плохо: return КраскаОбъявлений.плохоФон
        case .внимание: return КраскаОбъявлений.предупреждениеФон
        case .обычная: return Theme.оттенокАкцента
        }
    }

    var body: some View {
        Button(action: действие) {
            HStack(spacing: 6) {
                if занято {
                    ProgressView().tint(текст)
                } else if let значок {
                    Image(systemName: значок).accessibilityHidden(true)
                }
                Text(подпись)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(текст)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .background(фон, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(занято)
    }
}

/// Рамка карточки раздела (.dlv-card, аренда, .exch2): поверхность, рамка, скругление.
struct КарточкаРаздела<Содержимое: View>: View {
    let содержимое: Содержимое

    init(@ViewBuilder содержимое: () -> Содержимое) {
        self.содержимое = содержимое()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            содержимое
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1.5)
        }
    }
}

/// Метка статуса (.dlv-pill, цвет статуса аренды).
struct МеткаСтатуса: View {
    let текст: String
    var тон: ЗаметкаБизнеса.Тон = .серый

    var body: some View {
        Text(текст)
            .font(.system(size: 11.5, weight: .heavy))
            .foregroundStyle(краска)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(фон, in: Capsule())
    }

    private var краска: Color {
        switch тон {
        case .серый: return Theme.текстВторой
        case .предупреждение: return КраскаОбъявлений.предупреждениеТекст
        case .хорошо: return КраскаОбъявлений.хорошоТекст
        case .плохо: return КраскаОбъявлений.плохоТекст
        case .инфо: return КраскаОбъявлений.инфоТекст
        }
    }

    private var фон: Color {
        switch тон {
        case .серый: return Theme.поверхность2
        case .предупреждение: return КраскаОбъявлений.предупреждениеФон
        case .хорошо: return КраскаОбъявлений.хорошоФон
        case .плохо: return КраскаОбъявлений.плохоФон
        case .инфо: return КраскаОбъявлений.инфоФон
        }
    }
}

/// Миниатюра товара: картинка сайта или серая заглушка со значком.
struct МиниатюраРаздела: View {
    let адрес: URL?
    var размер: CGFloat = 52

    var body: some View {
        КартинкаЛенты(адрес, пунктов: размер) {
            ZStack {
                Theme.поверхность2
                Image(systemName: "shippingbox")
                    .foregroundStyle(Theme.текстВторой)
            }
        }
        .frame(width: размер, height: размер)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        .accessibilityHidden(true)
    }
}

// MARK: - Файлы кабинета (ZIP, CSV)

/**
 Файл кабинета по GET (пакет ФНО, сверка CSV): сайт открывает такие адреса окном браузера (window.location.href), и
 браузер их скачивает. fetch изнутри страницы возвращает текст — ZIP в нём испортится, поэтому здесь URLSession с куками
 сайта из хранилища WebKit (SiteSession.куки): запрос только читает, сессию он не меняет. Ответ JSON — это отказ сервера
 (нет PRO, нет продаж), его текст показывается человеку.
 */
@MainActor
enum ФайлыКабинета {
    struct Отказ: Error {
        let текст: String
    }

    static func скачать(_ хвост: String, запасноеИмя: String) async throws -> URL {
        guard let адрес = Config.страницаСайта(хвост) else { throw Отказ(текст: КабинетПлюсText.т("err_generic")) }
        var запрос = URLRequest(url: адрес)
        запрос.timeoutInterval = 90
        let куки = await SiteSession.куки()
        for (имя, значение) in куки {
            запрос.setValue(значение, forHTTPHeaderField: имя)
        }
        if let откуда = Config.страницаСайта("cabinet.php") {
            запрос.setValue(откуда.absoluteString, forHTTPHeaderField: "Referer")
        }
        let пара: (Data, URLResponse)
        do {
            пара = try await URLSession.shared.data(for: запрос)
        } catch {
            throw Отказ(текст: КабинетПлюсText.т("no_conn"))
        }
        let данные = пара.0
        let ответ = пара.1
        let http = ответ as? HTTPURLResponse
        let тип = (http?.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        if тип.contains("json") || тип.contains("text/html") {
            if let j = (try? JSONSerialization.jsonObject(with: данные)) as? [String: Any] {
                if МоиОбъявленияAPI.нетСессии(j) { throw Отказ(текст: CabinetText.т("signed_out")) }
                throw Отказ(текст: ЗапросыКабинета.текстОшибки(j))
            }
            if тип.contains("text/html") { throw Отказ(текст: КабинетПлюсText.т("err_generic")) }
        }
        guard (http?.statusCode ?? 200) < 400, !данные.isEmpty else {
            throw Отказ(текст: КабинетПлюсText.т("err_generic"))
        }
        let имя = имяИзЗаголовка(http?.value(forHTTPHeaderField: "Content-Disposition") ?? "") ?? запасноеИмя
        let файл = FileManager.default.temporaryDirectory.appendingPathComponent(имя)
        try? FileManager.default.removeItem(at: файл)
        do {
            try данные.write(to: файл, options: .atomic)
        } catch {
            throw Отказ(текст: КабинетПлюсText.т("err_generic"))
        }
        return файл
    }

    /// filename="…" или filename*=UTF-8''… из Content-Disposition; без каталогов и запрещённых знаков.
    private static func имяИзЗаголовка(_ заголовок: String) -> String? {
        var имя: String? = nil
        if let r = заголовок.range(of: "filename\\*=UTF-8''[^;]+", options: [.regularExpression, .caseInsensitive]) {
            let сырое = String(заголовок[r]).replacingOccurrences(of: "filename*=UTF-8''", with: "", options: .caseInsensitive)
            имя = сырое.removingPercentEncoding
        } else if let r = заголовок.range(of: "filename=\"?[^\";]+", options: [.regularExpression, .caseInsensitive]) {
            имя = String(заголовок[r]).replacingOccurrences(of: "filename=", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "\"", with: "")
        }
        guard let сырое = имя else { return nil }
        let запрещённые = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let чистое = сырое.components(separatedBy: запрещённые).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return чистое.isEmpty ? nil : String(чистое.prefix(120))
    }
}

/// Файл для системного листа «Поделиться» (item для .sheet).
struct ФайлДляЛиста: Identifiable {
    let id = UUID()
    let адрес: URL
}

/// Поле ввода в краске сайта (.inp): подпись сверху, рамка, фон поверхности.
struct ПолеРаздела: View {
    let подпись: String
    @Binding var текст: String
    var подсказка: String = ""
    var цифры = false
    var клавиатура: UIKeyboardType? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(подпись)
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(Theme.текстВторой)
            TextField(подсказка, text: Binding(get: { текст }, set: { новое in
                текст = цифры ? новое.filter { $0.isASCII && $0.isNumber } : новое
            }))
            .keyboardType(клавиатура ?? (цифры ? .numberPad : .default))
            .font(.system(size: 15))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                    .strokeBorder(Theme.линия, lineWidth: 1.5)
            }
            .accessibilityLabel(подпись)
        }
    }
}

/// Строка «адрес — Копировать» (.intg-copy сайта): моноширинный текст и кнопка.
struct СтрокаКопирования: View {
    let текст: String
    let скопировано: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(текст)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(Theme.текст)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(КабинетПлюсText.т("ig_copy")) {
                UIPasteboard.general.string = текст
                скопировано()
            }
            .font(.system(size: 13, weight: .bold))
            .tint(Theme.акцент)
        }
        .padding(10)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
    }
}
