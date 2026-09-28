import SwiftUI
import UIKit
import MapKit
import SafariServices

/**
 ОТСЛЕЖИВАНИЕ ДОСТАВКИ — ЭКРАНЫ (модель — TrackingModel.swift, служба — TrackingService.swift).

 Всё внутри приложения, своими видами SwiftUI:
   · ПилюляТрека / ПилюляТрекаСделки — короткий статус для списка сделок и переписки (из кэша, без сети);
   · КарточкаОтслеживания — «Отслеживание»: перевозчик, крупный статус, полоса этапов, сроки, курьер (машина, цвет,
     код, звонок), лента событий с точками и линией, «Обновлено N мин назад», «Изменить трек или ссылку»;
   · БлокОтслеживания — карточка со своей службой и опросом (для карточки сделки);
   · ЭкранОтслеживания — то же отдельным экраном со «потяните, чтобы обновить».
 Лист Safari — только последний выход, когда статусов нет ни у сервера, ни у перевозчика (и всё равно внутри
 приложения). Шрифты — текстовые стили (Dynamic Type), отступы — leading/trailing (арабский справа налево), цвета —
 токены Theme (тёмная тема).
 */

// MARK: - Формат дат и сроков

enum ФорматТрека {
    private static func формат(_ шаблон: String) -> DateFormatter {
        let ф = DateFormatter()
        ф.locale = ТрекText.локаль
        ф.setLocalizedDateFormatFromTemplate(шаблон)
        return ф
    }

    static func время(_ д: Date) -> String { формат("HHmm").string(from: д) }
    static func день(_ д: Date) -> String { формат("dMMM").string(from: д) }
    static func деньВремя(_ д: Date) -> String { формат("dMMMHHmm").string(from: д) }

    /// Время события: сегодня — «14:35», иначе «12 окт., 14:35».
    static func когда(_ д: Date) -> String {
        Calendar.current.isDateInToday(д) ? время(д) : деньВремя(д)
    }

    /// Срок: перевозчик — «12 окт.» или «12 окт. – 14 окт.»; курьер — «вот-вот», «через ~N мин · 14:35», «к 14:35».
    static func срок(_ с: СрокТрека, сейчас: Date) -> String {
        if с.цель == .доставка {
            if let до = с.до, !Calendar.current.isDate(до, inSameDayAs: с.когда) {
                return день(с.когда) + " – " + день(до)
            }
            return день(с.когда)
        }
        let осталось = с.когда.timeIntervalSince(сейчас)
        if осталось <= 90 { return ТрекText.т("eta_soon") }
        let минут = Int((осталось / 60).rounded())
        if минут < 60 { return String(format: ТрекText.т("eta_min"), минут, время(с.когда)) }
        return String(format: ТрекText.т("eta_at"), время(с.когда))
    }

    /// Подпись срока — от роли (clocalEtaHtml сайта).
    static func подписьСрока(_ цель: ЦельСрокаТрека, продавец: Bool) -> String {
        switch цель {
        case .доставка:    return ТрекText.т("eta")
        case .кПродавцу:   return ТрекText.т(продавец ? "eta_to_you" : "eta_to_seller")
        case .кПокупателю: return ТрекText.т(продавец ? "eta_to_buyer" : "eta_to_you2")
        case .обратно:     return ТрекText.т(продавец ? "eta_to_you" : "eta_back")
        }
    }

    /// «Обновлено только что», «Обновлено 5 мин назад», «Обновлено 14:35».
    static func обновлено(_ д: Date, сейчас: Date) -> String {
        let минут = Int(max(0, сейчас.timeIntervalSince(д)) / 60)
        if минут < 1 { return ТрекText.т("updated_now") }
        if минут < 60 { return String(format: ТрекText.т("updated_min"), минут) }
        return String(format: ТрекText.т("updated_at"), когда(д))
    }
}

// MARK: - Пилюля статуса (список сделок, переписка)

struct ПилюляТрека: View {
    let данные: ДанныеТрека
    /// «СДЭК · В пути» вместо «В пути».
    var сНазванием = false

    var body: some View {
        let вид = данные.статус.вид
        let текст = сНазванием ? данные.название + " · " + данные.статус.коротко : данные.статус.коротко
        HStack(spacing: 5) {
            Image(systemName: данные.статус.символ)
                .font(.caption2.weight(.bold))
                .accessibilityHidden(true)
            Text(текст)
                .font(.caption.weight(.bold))
                .lineLimit(1)
            if данные.живой {
                Circle()
                    .fill(вид.цвет)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(вид.цвет)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(вид.фон, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// Пилюля по номеру сделки — из кэша (КэшТрека), без сети: для строк списка и баннера переписки. Нет данных — ничего.
struct ПилюляТрекаСделки: View {
    let сделка: String
    var сНазванием = false

    var body: some View {
        if let д = КэшТрека.прочитать(сделка), д.содержательно {
            ПилюляТрека(данные: д, сНазванием: сНазванием)
        }
    }
}

// MARK: - Мелкие части

/// Кружок перевозчика: фирменный цвет и знак.
struct ЗнакПеревозчикаТрека: View {
    let перевозчик: ПеревозчикТрека
    @ScaledMetric private var размер: CGFloat

    init(перевозчик: ПеревозчикТрека, размер: CGFloat = 40) {
        self.перевозчик = перевозчик
        _размер = ScaledMetric(wrappedValue: размер, relativeTo: .headline)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(перевозчик.цвет)
            Image(systemName: перевозчик.символ)
                .font(.system(size: размер * 0.44, weight: .semibold))
                .foregroundStyle(перевозчик.цветЗнака)
        }
        .frame(width: размер, height: размер)
        .accessibilityHidden(true)
    }
}

/// «Принято · В пути · Рядом · Вручено».
struct ПолосаЭтаповТрека: View {
    let статус: СтатусТрека

    var body: some View {
        let шаг = статус.шаг ?? 0
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(1...4, id: \.self) { i in
                    Capsule()
                        .fill(i <= шаг ? статус.вид.цвет : Theme.линия)
                        .frame(height: 5)
                }
            }
            HStack(spacing: 4) {
                ForEach(1...4, id: \.self) { i in
                    Text(ТрекText.т("step_" + String(i)))
                        .font(.caption2.weight(i == шаг ? .bold : .regular))
                        .foregroundStyle(i <= шаг ? Theme.текст : Theme.текстВторой)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: ТрекText.т("a11y_step"), шаг, 4))
        .accessibilityValue(статус.текст)
    }
}

/// Лента событий: точка и вертикальная линия слева (в арабском — справа), новые сверху, первая — цветом статуса.
struct ЛентаСобытийТрека: View {
    let события: [СобытиеТрека]
    @ScaledMetric(relativeTo: .subheadline) private var точка: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(события.enumerated()), id: \.offset) { номер, событие in
                строка(событие, первая: номер == 0, последняя: номер == события.count - 1)
            }
        }
    }

    private var колонка: CGFloat { max(точка, 14) }

    private func строка(_ с: СобытиеТрека, первая: Bool, последняя: Bool) -> some View {
        let краска = с.статус.вид.цвет
        return HStack(alignment: .top, spacing: 12) {
            Color.clear
                .frame(width: колонка, height: 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(с.текст.isEmpty ? с.статус.текст : с.текст)
                    .font(.subheadline.weight(первая ? .semibold : .regular))
                    .foregroundStyle(первая ? Theme.текст : Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
                if !подпись(с).isEmpty {
                    Text(подпись(с))
                        .font(.caption)
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, последняя ? 0 : 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(alignment: .topLeading) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(первая ? Color.clear : Theme.линия)
                    .frame(width: 2, height: 4)
                ZStack {
                    Circle()
                        .fill(первая ? краска : Theme.поверхность)
                    Circle()
                        .strokeBorder(первая ? краска : Theme.линия, lineWidth: 2)
                }
                .frame(width: точка, height: точка)
                Rectangle()
                    .fill(последняя ? Color.clear : Theme.линия)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: колонка)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    /// «12 окт., 14:35 · Алматы».
    private func подпись(_ с: СобытиеТрека) -> String {
        var части: [String] = []
        if let когда = с.когда { части.append(ФорматТрека.когда(когда)) }
        if !с.место.isEmpty { части.append(с.место) }
        return части.joined(separator: " · ")
    }
}

/// Курьер: имя, машина и цвет, кнопка звонка, код для курьера.
struct БлокКурьераТрека: View {
    let курьер: КурьерТрека
    let продавец: Bool
    let позвонить: () -> Void

    private func т(_ ключ: String) -> String { ТрекText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Theme.мята)
                    Image(systemName: "person.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.акцент)
                }
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(курьер.имя.isEmpty ? т("courier") : курьер.имя)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.текст)
                    if !курьер.описаниеМашины.isEmpty {
                        Text(курьер.описаниеМашины)
                            .font(.caption)
                            .foregroundStyle(Theme.текстВторой)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 8)
                if курьер.звонок {
                    Button(action: позвонить) {
                        Image(systemName: "phone.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.white)
                            .frame(width: 44, height: 44)
                            .background(Theme.зелёный, in: Circle())
                    }
                    .buttonStyle(НажатиеПанелиСайта(сжатие: 0.94))
                    .accessibilityLabel(т("call"))
                }
            }
            if !курьер.код.isEmpty {
                VStack(spacing: 4) {
                    Text(т(курьер.кодДля == "return" ? "code_ret" : (продавец ? "code_s" : "code_b")))
                        .font(.caption)
                        .foregroundStyle(Theme.текстВторой)
                        .multilineTextAlignment(.center)
                    Text(курьер.код)
                        .font(.title.weight(.heavy).monospaced())
                        .foregroundStyle(Theme.текст)
                        .environment(\.layoutDirection, .leftToRight)
                        .textSelection(.enabled)
                    if курьер.попыток > 0 {
                        Text(String(format: т("code_left"), курьер.попыток))
                            .font(.caption2)
                            .foregroundStyle(Theme.текстВторой)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(10)
                .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                .accessibilityElement(children: .combine)
            } else if курьер.кодВСМС {
                Text(т(продавец ? "code_sms_s" : "code_sms_b"))
                    .font(.caption)
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Theme.оттенокАкцента, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
    }
}

/// Где курьер сейчас — маленькая карта (yandex_pos / courier.lat,lon).
struct КартаКурьераТрека: View {
    let широта: Double
    let долгота: Double
    let подпись: String
    @State private var камера: MapCameraPosition = .automatic

    private var точка: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: широта, longitude: долгота)
    }

    var body: some View {
        Map(position: $камера, interactionModes: [.zoom, .pan]) {
            Marker(подпись, systemImage: "car.fill", coordinate: точка)
                .tint(Theme.зелёный)
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: 170)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .onAppear { навести() }
        .onChange(of: String(широта) + "," + String(долгота)) { _, _ in навести() }
        .accessibilityHidden(true)
    }

    private func навести() {
        let область = MKCoordinateRegion(center: точка, latitudinalMeters: 1800, longitudinalMeters: 1800)
        withAnimation(ДвижениеСайта.камера) {
            камера = .region(область)
        }
    }
}

// MARK: - Лист Safari (последний выход — всё равно внутри приложения)

struct АдресСафариТрека: Identifiable {
    let адрес: URL
    var id: String { адрес.absoluteString }
}

struct ЛистСафариТрека: UIViewControllerRepresentable {
    let адрес: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let настройка = SFSafariViewController.Configuration()
        настройка.entersReaderIfAvailable = false
        let окно = SFSafariViewController(url: адрес, configuration: настройка)
        окно.preferredControlTintColor = UIColor(Theme.зелёный)
        окно.dismissButtonStyle = .close
        return окно
    }

    func updateUIViewController(_ окно: SFSafariViewController, context: Context) {}
}

// MARK: - Карточка «Отслеживание»

struct КарточкаОтслеживания: View {
    @ObservedObject var служба: СлужбаОтслеживания
    /// Показывать «Изменить трек или ссылку» (сайт: не «сам», held/shipped — dealTrackLink).
    var можноМенять: Bool = false
    /// Текущая ссылка сделки (track_url) — подставляется в поле правки.
    var исходнаяСсылка: String = ""
    /// Трек сохранён — пусть карточка сделки перечитает сделку.
    var изменено: (() -> Void)? = nil

    @State private var всеСобытия = false
    @State private var правка = false
    @State private var сафари: АдресСафариТрека? = nil

    private func т(_ ключ: String) -> String { ТрекText.т(ключ) }

    private var запись: ДанныеТрека? { служба.состояние.запись }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            шапка
            содержимое
            if let текст = служба.плашка {
                Text(текст)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Theme.зелёный, in: Capsule())
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .animation(ДвижениеСайта.смена, value: служба.состояние)
        .animation(ДвижениеСайта.появление, value: служба.плашка)
        .sheet(isPresented: $правка) {
            ЛистПравкиТрека(служба: служба, исходное: исходноеПоле, изменено: изменено)
        }
        .sheet(item: $сафари) { цель in
            ЛистСафариТрека(адрес: цель.адрес)
                .ignoresSafeArea()
        }
        .alert(т("call_t"), isPresented: звонокНаЭкране, presenting: служба.звонок) { звонок in
            if let адрес = звонок.адрес {
                Button(т("call_go")) { UIApplication.shared.open(адрес) }
            }
            Button(т("close"), role: .cancel) {}
        } message: { звонок in
            Text(звонок.пояснение)
        }
    }

    private var звонокНаЭкране: Binding<Bool> {
        Binding(get: { служба.звонок != nil }, set: { показан in
            if !показан { служба.звонок = nil }
        })
    }

    private var исходноеПоле: String {
        if !исходнаяСсылка.isEmpty { return исходнаяСсылка }
        return запись?.номер ?? ""
    }

    // MARK: Шапка

    private var шапка: some View {
        HStack(spacing: 12) {
            ЗнакПеревозчикаТрека(перевозчик: запись?.перевозчик ?? .другой)
            VStack(alignment: .leading, spacing: 2) {
                Text(т("title"))
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(Theme.текстВторой)
                    .textCase(.uppercase)
                Text(запись?.название ?? т("c_other"))
                    .font(.headline)
                    .foregroundStyle(Theme.текст)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if запись?.живой == true {
                значокЖивой
            }
            кнопкаОбновить
        }
    }

    private var значокЖивой: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Theme.зелёныйЯркий)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(т("live"))
                .font(.caption2.weight(.bold))
                .lineLimit(1)
        }
        .foregroundStyle(Theme.акцент)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.оттенокАкцента, in: Capsule())
    }

    @ViewBuilder
    private var кнопкаОбновить: some View {
        if служба.обновляется {
            SiteSpinner.мелкий
                .frame(width: 36, height: 36)
        } else {
            Button {
                ОткликСайта.выбор()
                Task { await служба.обновить() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.текстВторой)
                    .frame(width: 36, height: 36)
                    .background(Theme.поверхность2, in: Circle())
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.92))
            .accessibilityLabel(т("refresh"))
        }
    }

    // MARK: Состояния

    @ViewBuilder
    private var содержимое: some View {
        switch служба.состояние {
        case .загрузка:
            заготовка
        case .данные(let д):
            основное(д)
        case .нетДанных(let д):
            пусто(д)
        case .ошибка(let текст):
            VStack(alignment: .leading, spacing: 10) {
                Label(текст, systemImage: "wifi.exclamationmark")
                    .font(.subheadline)
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
                малаяКнопка(т("retry"), символ: "arrow.clockwise") {
                    Task { await служба.обновить() }
                }
            }
        }
    }

    private var заготовка: some View {
        VStack(alignment: .leading, spacing: 10) {
            МерцаниеСайта(радиус: 6)
                .frame(width: 200, height: 22)
            МерцаниеСайта(радиус: 4)
                .frame(height: 6)
            ForEach(0..<3, id: \.self) { _ in
                МерцаниеСайта(радиус: 6)
                    .frame(height: 16)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ТрекText.т("title"))
    }

    @ViewBuilder
    private func основное(_ д: ДанныеТрека) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: д.статус.символ)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(д.статус.вид.цвет)
                    .accessibilityHidden(true)
                Text(д.подпись)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.текст)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if д.статус.шаг != nil {
                ПолосаЭтаповТрека(статус: д.статус)
            }
        }
        if !д.номер.isEmpty {
            строкаНомера(д.номер)
        }
        if !д.сроки.isEmpty {
            сроки(д)
        }
        if let к = д.курьер, !к.пусто {
            БлокКурьераТрека(курьер: к, продавец: д.продавец, позвонить: { служба.позвонитьКурьеру() })
        }
        if д.живой, let к = д.курьер, let широта = к.широта, let долгота = к.долгота {
            КартаКурьераТрека(широта: широта, долгота: долгота, подпись: к.имя.isEmpty ? т("courier") : к.имя)
        }
        if !д.события.isEmpty {
            история(д.события)
        }
        низ(д)
    }

    private func строкаНомера(_ номер: String) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(т("track_no"))
                    .font(.caption)
                    .foregroundStyle(Theme.текстВторой)
                Text(номер)
                    .font(.subheadline.monospaced().weight(.semibold))
                    .foregroundStyle(Theme.текст)
                    .environment(\.layoutDirection, .leftToRight)
                    .textSelection(.enabled)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            Button {
                UIPasteboard.general.string = номер
                ОткликСайта.выбор()
                служба.показать(т("copied"))
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.акцент)
                    .frame(width: 36, height: 36)
                    .background(Theme.оттенокАкцента, in: Circle())
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.92))
            .accessibilityLabel(т("copy"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
    }

    /// Сроки: «через ~N мин» пересчитывается раз в 30 с.
    private func сроки(_ д: ДанныеТрека) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { контекст in
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(д.сроки.enumerated()), id: \.offset) { _, срок in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "clock")
                            .font(.subheadline)
                            .foregroundStyle(Theme.текстВторой)
                            .accessibilityHidden(true)
                        Text(ФорматТрека.подписьСрока(срок.цель, продавец: д.продавец))
                            .font(.subheadline)
                            .foregroundStyle(Theme.текстВторой)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Text(ФорматТрека.срок(срок, сейчас: контекст.date))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.текст)
                            .multilineTextAlignment(.trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func история(_ события: [СобытиеТрека]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(т("events"))
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(Theme.текст)
                .accessibilityAddTraits(.isHeader)
            ЛентаСобытийТрека(события: всеСобытия ? события : Array(события.prefix(4)))
            if события.count > 4 {
                Button {
                    withAnimation(ДвижениеСайта.смена) { всеСобытия.toggle() }
                } label: {
                    Text(всеСобытия ? т("show_less") : String(format: т("show_all"), события.count))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.акцент)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// «Обновлено N мин назад» и «Изменить трек или ссылку».
    private func низ(_ д: ДанныеТрека) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TimelineView(.periodic(from: .now, by: 30)) { контекст in
                Text(ФорматТрека.обновлено(д.обновлено, сейчас: контекст.date))
                    .font(.caption)
                    .foregroundStyle(Theme.текстВторой)
            }
            if можноМенять {
                малаяКнопка(т("edit"), символ: "pencil") { правка = true }
            }
        }
    }

    /// Статусов нет: что известно (номер), пояснение, страница перевозчика листом Safari, правка.
    private func пусто(_ д: ДанныеТрека?) -> some View {
        let естьТрек = д != nil && (!(д?.номер ?? "").isEmpty || !(д?.ссылка ?? "").isEmpty)
        return VStack(alignment: .leading, spacing: 12) {
            if let номер = д?.номер, !номер.isEmpty {
                строкаНомера(номер)
            }
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "hourglass")
                    .font(.title3)
                    .foregroundStyle(Theme.текстВторой)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(т(естьТрек ? "no_data_t" : "no_track_t"))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.текст)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(т(естьТрек ? "no_data_s" : "no_track_s"))
                        .font(.footnote)
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            if let адрес = д?.запаснаяСтраница {
                малаяКнопка(т("open_carrier"), символ: "safari") {
                    сафари = АдресСафариТрека(адрес: адрес)
                }
            }
            if можноМенять {
                малаяКнопка(т(естьТрек ? "edit" : "add"), символ: естьТрек ? "pencil" : "plus") { правка = true }
            }
        }
    }

    private func малаяКнопка(_ текст: String, символ: String, действие: @escaping () -> Void) -> some View {
        Button(action: действие) {
            Label(текст, systemImage: символ)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.акцент)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Theme.оттенокАкцента, in: Capsule())
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
    }
}

// MARK: - Лист «Трек-номер или ссылка» (dealTrackOpen / dealTrackSniff / dealTrackSave сайта)

struct ЛистПравкиТрека: View {
    @ObservedObject var служба: СлужбаОтслеживания
    let исходное: String
    var изменено: (() -> Void)? = nil

    @Environment(\.dismiss) private var закрыть
    @State private var ввод: String
    @State private var вБуфереСсылка = false
    @FocusState private var фокус: Bool

    init(служба: СлужбаОтслеживания, исходное: String, изменено: (() -> Void)? = nil) {
        self.служба = служба
        self.исходное = исходное
        self.изменено = изменено
        _ввод = State(initialValue: исходное)
    }

    private func т(_ ключ: String) -> String { ТрекText.т(ключ) }

    private var найден: НайденныйТрек? { ОпределениеПеревозчика.изТекста(ввод) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(т("edit_hint"))
                        .font(.footnote)
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                    поле
                    определение
                    вставка
                    кнопкаСохранить
                    if !исходное.isEmpty {
                        Button(role: .destructive) {
                            сохранить("")
                        } label: {
                            Text(т("remove"))
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 40)
                        }
                        .disabled(служба.сохраняется)
                    }
                }
                .padding(20)
            }
            .background(Theme.поверхность.ignoresSafeArea())
            .navigationTitle(т("edit_t"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(т("close")) { закрыть() }
                }
            }
            .alert(служба.ошибкаПравки?.заголовок ?? "", isPresented: ошибкаНаЭкране) {
                Button(т("close"), role: .cancel) {}
            } message: {
                Text(служба.ошибкаПравки?.текст ?? "")
            }
            .onAppear {
                /* dealTrackSniff: поле пустое — смотрим, есть ли в буфере ссылка. hasURLs не читает сам буфер и не
                   поднимает системный вопрос «Разрешить вставку»; вставляет только PasteButton по нажатию. */
                вБуфереСсылка = ввод.isEmpty && UIPasteboard.general.hasURLs
                if ввод.isEmpty { фокус = true }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var ошибкаНаЭкране: Binding<Bool> {
        Binding(get: { служба.ошибкаПравки != nil }, set: { показана in
            if !показана { служба.ошибкаПравки = nil }
        })
    }

    private var поле: some View {
        TextField(т("edit_ph"), text: $ввод, axis: .vertical)
            .lineLimit(1...4)
            .font(.body)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .focused($фокус)
            .environment(\.layoutDirection, .leftToRight)
            .padding(12)
            .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                    .strokeBorder(фокус ? Theme.акцент : Theme.линия, lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
    }

    @ViewBuilder
    private var определение: some View {
        let t = ввод.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty {
            if let н = найден {
                HStack(spacing: 8) {
                    ЗнакПеревозчикаТрека(перевозчик: н.перевозчик, размер: 24)
                    Text(String(format: т("detected"), н.перевозчик.название))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.акцент)
                }
            } else {
                Label(т("detected_none"), systemImage: "questionmark.circle")
                    .font(.footnote)
                    .foregroundStyle(Theme.текстВторой)
            }
        }
    }

    private var вставка: some View {
        VStack(alignment: .leading, spacing: 6) {
            PasteButton(payloadType: String.self) { строки in
                let текст = строки.first ?? ""
                DispatchQueue.main.async {
                    вставить(текст)
                }
            }
            .buttonBorderShape(.capsule)
            .tint(Theme.зелёный)
            .labelStyle(.titleAndIcon)
            if вБуфереСсылка {
                Text(т("clip_seen"))
                    .font(.caption)
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var кнопкаСохранить: some View {
        Button {
            сохранить(ввод)
        } label: {
            HStack(spacing: 8) {
                if служба.сохраняется {
                    SiteSpinner.мелкийБелый
                }
                Text(т("save"))
                    .font(.body.weight(.bold))
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(LinearGradient(colors: [Theme.зелёный, Theme.зелёный2], startPoint: .topLeading,
                                       endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .opacity(можноСохранить ? 1 : 0.55)
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
        .disabled(!можноСохранить)
    }

    private var можноСохранить: Bool {
        let t = ввод.trimmingCharacters(in: .whitespacesAndNewlines)
        return !служба.сохраняется && !t.isEmpty && t != исходное
    }

    /// trkPaste: из вставленного текста — ссылка службы, иначе номер известного формата, иначе как есть.
    private func вставить(_ текст: String) {
        let ссылка = ОпределениеПеревозчика.найтиСсылку(текст)
        if !ссылка.isEmpty {
            ввод = ссылка
        } else if let н = ОпределениеПеревозчика.изТекста(текст), !н.номер.isEmpty {
            ввод = н.номер
        } else {
            ввод = String(текст.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        }
        вБуфереСсылка = false
        ОткликСайта.выбор()
    }

    private func сохранить(_ значение: String) {
        фокус = false
        Task { @MainActor in
            if await служба.сохранить(значение) {
                изменено?()
                закрыть()
            }
        }
    }
}

// MARK: - Готовые сборки

/// Карточка со своей службой и опросом — для карточки сделки. повод — подпись сделки (sig): сменилась — обновить.
struct БлокОтслеживания: View {
    @StateObject private var служба: СлужбаОтслеживания
    let повод: String
    let можноМенять: Bool
    let исходнаяСсылка: String
    let изменено: (() -> Void)?
    @Environment(\.scenePhase) private var фаза

    init(сделка: String, данные: [String: Any]? = nil, повод: String = "", можноМенять: Bool = false,
         исходнаяСсылка: String = "", изменено: (() -> Void)? = nil) {
        _служба = StateObject(wrappedValue: СлужбаОтслеживания(сделка: сделка, данные: данные))
        self.повод = повод
        self.можноМенять = можноМенять
        self.исходнаяСсылка = исходнаяСсылка
        self.изменено = изменено
    }

    var body: some View {
        КарточкаОтслеживания(служба: служба, можноМенять: можноМенять, исходнаяСсылка: исходнаяСсылка,
                             изменено: изменено)
            .task { await служба.следить() }
            .onChange(of: повод) { _, _ in
                Task { await служба.обновить(вФоне: true) }
            }
            .onChange(of: фаза) { _, новая in
                if новая == .active { Task { await служба.обновить(вФоне: true) } }
            }
    }
}

/// Отдельный экран «Отслеживание» (из пилюли списка или переписки): потяните вниз — обновить.
struct ЭкранОтслеживания: View {
    @StateObject private var служба: СлужбаОтслеживания
    let можноМенять: Bool

    init(сделка: String, можноМенять: Bool = false) {
        _служба = StateObject(wrappedValue: СлужбаОтслеживания(сделка: сделка))
        self.можноМенять = можноМенять
    }

    var body: some View {
        ScrollView {
            КарточкаОтслеживания(служба: служба, можноМенять: можноМенять)
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
        }
        .refreshable { await служба.обновить() }
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .navigationTitle(ТрекText.т("title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await служба.следить() }
    }
}
