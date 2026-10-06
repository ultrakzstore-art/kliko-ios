import SwiftUI
import UIKit
import MapKit
import CoreLocation
import AVFoundation
import Vision
import ImageIO
import CoreImage.CIFilterBuiltins

/**
 СДЕЛКА С ПОДПИСЬЮ eGov — ДЕТАЛИ ОКНА (стили .eds-* модуля сайта js/cabinet-eds.min.js в краске кабинета).

 Кирпичи: секция (.eds-sec), заголовок секции, заметка (.eds-note), плашки (.eds-warn / .eds-bad / .eds-okb), пилюля
 статуса (.eds-pill), кнопки (.btn-g / .btn-w), ряд кнопок (.eds-btns), подпись стороны (.eds-sig), строка «ключ —
 значение» (.eds-kv), полоса шагов (.eds-steps), вариант доставки (.eds-opt), поле (.eds-f), флажок (.eds-chk), код
 (.eds-code) и QR (CoreImage вместо qrcode.min.js), тост. Окна: вопрос с полем (cabPrompt), точка доставки на карте
 (hovAddrOpen «to» — своя MapKit-точка), карта курьера (clcYaMapSync), сканер карты (edsCardScan: камера и распознавание
 текста Vision на самом телефоне — снимок никуда не уходит, как у Tesseract сайта), геопозиция встречи (_edsGeo).
 */

// MARK: - Краски

extension ВидПлашкиEDS {
    var фон: Color {
        switch self {
        case .инфо:     return КраскаСделокКабинета.инфоФон
        case .внимание: return КраскаСделокКабинета.предупреждениеФон
        case .хорошо:   return КраскаСделокКабинета.хорошоФон
        case .плохо:    return КраскаСделокКабинета.плохоФон
        case .нет:      return Theme.поверхность2
        }
    }

    var текст: Color {
        switch self {
        case .инфо:     return КраскаСделокКабинета.инфоТекст
        case .внимание: return КраскаСделокКабинета.предупреждениеТекст
        case .хорошо:   return КраскаСделокКабинета.хорошоТекст
        case .плохо:    return КраскаСделокКабинета.плохоТекст
        case .нет:      return Theme.текстВторой
        }
    }
}

extension ТочкаEDS {
    var координата: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: широта, longitude: долгота) }
}

// MARK: - Пилюля статуса (.eds-pill)

struct ПилюляEDS: View {
    let вид: ВидПлашкиEDS
    let текст: String
    /// В строке списка — одна строка (ровная схема карточек), длинный статус ужимается; в окне сделки — до двух.
    var вОднуСтроку: Bool = false

    var body: some View {
        Text(текст)
            .font(.system(size: 11, weight: .bold))
            .lineLimit(вОднуСтроку ? 1 : 2)
            .minimumScaleFactor(вОднуСтроку ? 0.8 : 1)
            .multilineTextAlignment(.center)
            .foregroundStyle(вид.текст)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(вид.фон, in: Capsule())
    }
}

// MARK: - Секция (.eds-sec)

struct СекцияEDS<Содержимое: View>: View {
    let содержимое: Содержимое

    init(@ViewBuilder _ содержимое: () -> Содержимое) {
        self.содержимое = содержимое()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            содержимое
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
    }
}

/// .eds-sec-h: значок 16 и заголовок 15/800.
struct ЗаголовокEDS: View {
    let текст: String
    let символ: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: символ)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(КраскаСделокКабинета.хорошоТекст)
                .accessibilityHidden(true)
            Text(текст)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityAddTraits(.isHeader)
    }
}

/// .eds-note: 13, серый, межстрочие 1.45.
struct ЗаметкаEDS: View {
    let текст: Text

    init(_ строка: String) {
        self.текст = Text(строка)
    }

    init(текст: Text) {
        self.текст = текст
    }

    var body: some View {
        текст
            .font(.system(size: 13))
            .lineSpacing(3)
            .foregroundStyle(Theme.текстВторой)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// .eds-warn / .eds-bad / .eds-okb: плашка на оттенке, радиус 10, 14 (у .eds-okb — жирный).
struct ПлашкаEDS: View {
    let вид: ВидПлашкиEDS
    let текст: Text

    init(_ вид: ВидПлашкиEDS, _ строка: String) {
        self.вид = вид
        self.текст = Text(строка)
    }

    init(_ вид: ВидПлашкиEDS, текст: Text) {
        self.вид = вид
        self.текст = текст
    }

    var body: some View {
        текст
            .font(.system(size: 14, weight: вид == .хорошо ? .bold : .regular))
            .lineSpacing(3)
            .foregroundStyle(вид.текст)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(вид.фон, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
    }
}

// MARK: - Кнопки (.btn-g / .btn-w, .eds-btns)

struct КнопкаEDS: View {
    let надпись: String
    var символ: String? = nil
    var главная = true
    var занята = false
    var доступна = true
    let действие: () -> Void

    init(_ надпись: String, символ: String? = nil, главная: Bool = true, занята: Bool = false, доступна: Bool = true,
         действие: @escaping () -> Void) {
        self.надпись = надпись
        self.символ = символ
        self.главная = главная
        self.занята = занята
        self.доступна = доступна
        self.действие = действие
    }

    var body: some View {
        Button(action: действие) {
            ЯрлыкКнопкиEDS(надпись: надпись, символ: символ, главная: главная, занята: занята, доступна: доступна)
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
        .disabled(!доступна || занята)
        .accessibilityLabel(надпись)
    }
}

/// Вид кнопки .btn-g (зелёный градиент) / .btn-w (белая в рамке) — и для PhotosPicker, ShareLink.
struct ЯрлыкКнопкиEDS: View {
    let надпись: String
    var символ: String? = nil
    var главная = true
    var занята = false
    var доступна = true

    var body: some View {
        HStack(spacing: 6) {
            if занята {
                Text(verbatim: "…")
                    .font(.system(size: 15, weight: .heavy))
            } else {
                if let символ {
                    Image(systemName: символ)
                        .font(.system(size: 15, weight: .semibold))
                        .accessibilityHidden(true)
                }
                Text(надпись)
                    .font(.system(size: 14, weight: .bold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(главная ? Color.white : Theme.текст)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 46)
        .background {
            if главная {
                RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.зелёный, Theme.зелёный2], startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
                    .shadow(color: КраскаСделокКабинета.теньКнопки, radius: 4, x: 0, y: 5)
            } else {
                RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                    .fill(Theme.поверхность)
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                            .strokeBorder(Theme.линия, lineWidth: 1.5)
                    }
            }
        }
        .opacity(доступна ? 1 : 0.55)
        .contentShape(Rectangle())
    }
}

/// .eds-btns: кнопки в ряд (flex 1 1 160px), не влезают — столбиком.
struct РядКнопокEDS<Содержимое: View>: View {
    let содержимое: Содержимое

    init(@ViewBuilder _ содержимое: () -> Содержимое) {
        self.содержимое = содержимое()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { содержимое }
            VStack(spacing: 8) { содержимое }
        }
    }
}

// MARK: - Подпись стороны (.eds-sig), строка (.eds-kv), шаги (.eds-steps)

struct ПодписьСтороныEDS: View {
    let текст: String
    /// nil — ещё не подписал(а); иначе время подписи (может быть пустым).
    let когда: String?

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            ZStack {
                Circle()
                    .fill(когда != nil ? КраскаСделокКабинета.акцент : Theme.поверхность2)
                Image(systemName: когда != nil ? "checkmark" : "clock")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(когда != nil ? Color.white : Theme.текстВторой)
            }
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)
            Text(текст)
                .font(.system(size: 14))
                .foregroundStyle(Theme.текст)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            Text(состояние)
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var состояние: String {
        guard let когда else { return EDSText.т("eds_not_signed") }
        let время = ФорматEDS.когда(когда)
        return время.isEmpty ? EDSText.т("eds_signed_at") : EDSText.т("eds_signed_at") + " " + время
    }
}

struct СтрокаEDS: View {
    let ключ: String
    let значение: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(ключ)
                .foregroundStyle(Theme.текстВторой)
            Spacer(minLength: 8)
            Text(значение)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(Theme.текст)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .font(.system(size: 14))
        .accessibilityElement(children: .combine)
    }
}

struct ШагиEDS: View {
    let названия: [String]
    let текущий: Int

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            ForEach(Array(названия.enumerated()), id: \.offset) { пара in
                let пройден = пара.offset <= текущий
                VStack(spacing: 4) {
                    Capsule()
                        .fill(пройден ? КраскаСделокКабинета.акцент : Theme.линия)
                        .frame(height: 4)
                    Text(пара.element)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(пройден ? КраскаСделокКабинета.хорошоТекст : Theme.текстВторой)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityValue(пройден ? EDSText.т("a11y_step_done") : "")
            }
        }
    }
}

// MARK: - Вариант доставки (.eds-opt)

struct ВариантEDS: View {
    let символ: String
    let заголовок: String
    let подпись: String
    let выбран: Bool
    var доступен = true
    let действие: () -> Void

    var body: some View {
        Button(action: действие) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: символ)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(КраскаСделокКабинета.акцент)
                    .frame(width: 32, height: 32)
                    .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(заголовок)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.текст)
                    Text(подпись)
                        .font(.system(size: 13))
                        .lineSpacing(2)
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(выбран ? КраскаСделокКабинета.хорошоФон : Theme.поверхность,
                        in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                    .strokeBorder(выбран ? КраскаСделокКабинета.акцент : Theme.линия, lineWidth: 1.5)
            }
            .contentShape(Rectangle())
            .opacity(доступен ? 1 : 0.55)
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
        .disabled(!доступен)
        .accessibilityAddTraits(выбран ? .isSelected : [])
    }
}

// MARK: - Поля (.eds-f), флажок (.eds-chk)

/// Подпись поля: 12/700 серым.
struct ПодписьПоляEDS: View {
    let текст: String

    var body: some View {
        Text(текст)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Theme.текстВторой)
    }
}

/// .eds-f input: 16, поля 8/10, рамка 1 --line (ошибка — --on-bad), радиус 10.
struct ПолеEDS: ViewModifier {
    var ошибка = false

    func body(content: Content) -> some View {
        content
            .font(.system(size: 16))
            .foregroundStyle(Theme.текст)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                    .strokeBorder(ошибка ? КраскаСделокКабинета.плохоТекст : Theme.линия, lineWidth: 1)
            }
    }
}

struct ФлажокEDS: View {
    @Binding var включён: Bool
    let текст: String

    var body: some View {
        Button {
            включён.toggle()
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: включён ? "checkmark.square.fill" : "square")
                    .font(.system(size: 17))
                    .foregroundStyle(КраскаСделокКабинета.акцент)
                Text(текст)
                    .font(.system(size: 13))
                    .lineSpacing(2)
                    .foregroundStyle(Theme.текстВторой)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(включён ? .isSelected : [])
    }
}

// MARK: - Код и QR (.eds-code, .eds-qr)

struct КодEDS: View {
    let текст: String

    var body: some View {
        Text(текст)
            .font(.system(size: 40, weight: .heavy))
            .tracking(7)
            .monospacedDigit()
            .foregroundStyle(Theme.текст)
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity)
            .textSelection(.enabled)
    }
}

enum КартинкаQREDS {
    /// QR ссылки: уровень M, чёрный на белом, модуль — 8 пикселей без сглаживания.
    static func сделать(_ текст: String) -> UIImage? {
        guard !текст.isEmpty else { return nil }
        let фильтр = CIFilter.qrCodeGenerator()
        фильтр.message = Data(текст.utf8)
        фильтр.correctionLevel = "M"
        guard let код = фильтр.outputImage else { return nil }
        let крупно = код.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let готово = CIContext().createCGImage(крупно, from: крупно.extent.integral) else { return nil }
        return UIImage(cgImage: готово)
    }
}

/// .eds-qr: 200×200 на белом, поля 8, радиус 10.
struct QREDS: View {
    let картинка: UIImage?

    init(_ текст: String) {
        картинка = КартинкаQREDS.сделать(текст)
    }

    var body: some View {
        if let картинка {
            Image(uiImage: картинка)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 184, height: 184)
                .padding(8)
                .background(Color.white, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                .frame(maxWidth: .infinity)
                .accessibilityLabel(EDSText.т("a11y_qr"))
        }
    }
}

// MARK: - Тост

/// .toast кабинета: #0f1712, белый 14, радиус 12.
struct ТостEDS: View {
    let текст: String

    var body: some View {
        Text(текст)
            .font(.system(size: 14))
            .lineSpacing(2)
            .foregroundStyle(Color.white)
            .multilineTextAlignment(.center)
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .background(Color(red: 15 / 255, green: 23 / 255, blue: 18 / 255).opacity(0.94),
                        in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .frame(maxWidth: 420)
            .padding(.horizontal, 16)
            .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - Протокол (details.eds-sec)

struct СвёрткаEDS<Содержимое: View>: View {
    let заголовок: String
    let подпись: String
    let символ: String
    let содержимое: Содержимое
    @State private var открыт = false

    init(заголовок: String, подпись: String, символ: String, @ViewBuilder _ содержимое: () -> Содержимое) {
        self.заголовок = заголовок
        self.подпись = подпись
        self.символ = символ
        self.содержимое = содержимое()
    }

    var body: some View {
        СекцияEDS {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { открыт.toggle() }
            } label: {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: символ)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(КраскаСделокКабинета.хорошоТекст)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(заголовок)
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(Theme.текст)
                        Text(подпись)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.текстВторой)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 6)
                    Text(EDSText.т(открыт ? "eds_hide" : "eds_show"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(КраскаСделокКабинета.акцент)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(КраскаСделокКабинета.акцент)
                        .rotationEffect(.degrees(открыт ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            if открыт {
                содержимое
            }
        }
    }
}

// MARK: - Вопрос с полем (cabPrompt)

struct ЛистВопросаEDS: View {
    let заголовок: String
    let текст: String
    let подсказка: String
    let кнопка: String
    let отмена: String
    var опасно = false
    let ответ: (String) -> Void
    let закрыть: () -> Void

    @State private var значение = ""
    @FocusState private var фокус: Bool

    /// Свой init: с private @State встроенный был бы private — его не позвать из окна сделки (EdsDealView).
    init(заголовок: String, текст: String, подсказка: String, кнопка: String, отмена: String, опасно: Bool = false,
         ответ: @escaping (String) -> Void, закрыть: @escaping () -> Void) {
        self.заголовок = заголовок
        self.текст = текст
        self.подсказка = подсказка
        self.кнопка = кнопка
        self.отмена = отмена
        self.опасно = опасно
        self.ответ = ответ
        self.закрыть = закрыть
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(заголовок)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .accessibilityAddTraits(.isHeader)
                if !текст.isEmpty {
                    Text(текст)
                        .font(.system(size: 14))
                        .lineSpacing(3)
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                }
                TextField(подсказка, text: $значение, axis: .vertical)
                    .lineLimit(3...6)
                    .focused($фокус)
                    .onChange(of: значение) { _, новое in
                        if новое.count > 1000 { значение = String(новое.prefix(1000)) }
                    }
                    .modifier(ПолеEDS())
                HStack(spacing: 10) {
                    Button {
                        закрыть()
                    } label: {
                        Text(отмена)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.текст)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(Theme.поверхность2,
                                        in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                    }
                    .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
                    Button {
                        let итог = значение.trimmingCharacters(in: .whitespacesAndNewlines)
                        закрыть()
                        ответ(итог)
                    } label: {
                        Text(кнопка)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.white)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(опасно ? Color(red: 185 / 255, green: 28 / 255, blue: 28 / 255)
                                              : КраскаСделокКабинета.хорошоТекст,
                                        in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                    }
                    .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
                }
                .padding(.top, 4)
            }
            .padding(20)
            .мерилоЛиста()
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.поверхность.ignoresSafeArea())
        .листПоВысоте()
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { фокус = true }
        }
    }
}

// MARK: - Геопозиция (_edsGeo)

/// Одна геопозиция телефона: 7 с на ответ; нет разрешения или ответа — nil.
@MainActor
final class ГеоEDS: NSObject, CLLocationManagerDelegate {
    private let менеджер = CLLocationManager()
    private var ждём: CheckedContinuation<CLLocation?, Never>? = nil
    private var таймер: Task<Void, Never>? = nil

    /// {lat, lon, acc} для протокола встречи (_edsGeo сайта).
    static func одноМесто() async -> [String: Any]? {
        let гео = ГеоEDS()
        guard let место = await гео.запросить(секунд: 7) else { return nil }
        let точность = место.horizontalAccuracy.isFinite ? max(0, место.horizontalAccuracy) : 0
        return ["lat": место.coordinate.latitude, "lon": место.coordinate.longitude, "acc": Int(точность.rounded())]
    }

    /// «Определить моё место» в окне карты.
    static func координата() async -> CLLocationCoordinate2D? {
        let гео = ГеоEDS()
        return await гео.запросить(секунд: 10)?.coordinate
    }

    private func запросить(секунд: Double) async -> CLLocation? {
        let статус = менеджер.authorizationStatus
        if статус == .denied || статус == .restricted { return nil }
        менеджер.delegate = self
        менеджер.desiredAccuracy = kCLLocationAccuracyBest
        return await withCheckedContinuation { (продолжение: CheckedContinuation<CLLocation?, Never>) in
            ждём = продолжение
            таймер = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(секунд * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.закончить(nil)
            }
            if статус == .notDetermined {
                менеджер.requestWhenInUseAuthorization()
            } else {
                менеджер.requestLocation()
            }
        }
    }

    private func закончить(_ место: CLLocation?) {
        таймер?.cancel()
        таймер = nil
        guard let продолжение = ждём else { return }
        ждём = nil
        менеджер.delegate = nil
        продолжение.resume(returning: место)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let статус = manager.authorizationStatus
        Task { @MainActor in
            guard self.ждём != nil else { return }
            switch статус {
            case .authorizedAlways, .authorizedWhenInUse:
                self.менеджер.requestLocation()
            case .denied, .restricted:
                self.закончить(nil)
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let место = locations.last
        Task { @MainActor in self.закончить(место) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.закончить(nil) }
    }
}

// MARK: - Точка доставки на карте (hovAddrOpen «to»)

/**
 Куда везти курьеру — то же окно, что «Куда доставить» в сделке (ЛистТочкиСделки): поиск адреса, карта с кнопкой
 «моё место», адрес по точке, «Встречу у подъезда», квартира, подъезд, этаж, домофон, комментарий, закреплённая
 «Сохранить». Окно отдаёт адрес, точку и дверь сюда — дальше ship_quote (вопрос о цене встанет, когда лист уедет).
 */
struct ЛистТочкиEDS: View {
    let адрес: String
    let дверь: ДверьEDS
    let выбрано: (String, ТочкаEDS?, ДверьEDS) -> Void

    init(адрес: String, дверь: ДверьEDS, выбрано: @escaping (String, ТочкаEDS?, ДверьEDS) -> Void) {
        self.адрес = адрес
        self.дверь = дверь
        self.выбрано = выбрано
    }

    private var цель: ТочкаНаКартеСделки {
        var д = ДверьСделки()
        д.уПодъезда = дверь.уПодъезда
        д.квартира = дверь.квартира
        д.подъезд = дверь.подъезд
        д.этаж = дверь.этаж
        д.домофон = дверь.домофон
        д.комментарий = дверь.заметка
        return ТочкаНаКартеСделки(сторона: "to", адрес: адрес, точка: nil, дверь: д)
    }

    var body: some View {
        ЛистТочкиСделки(цель: цель, модель: nil, выбрано: { итог in
            let точка = итог.точка.map { ТочкаEDS(широта: $0.latitude, долгота: $0.longitude) }
            let новая = ДверьEDS(итог.дверь)
            let отдать = выбрано
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                отдать(итог.адрес, точка, новая)
            }
        })
    }
}

// MARK: - Карта курьера (clcYaMapSync: A — откуда, B — куда, машина — курьер)

struct КартаКурьераEDS: View {
    let откуда: ТочкаEDS?
    let куда: ТочкаEDS?
    let где: ТочкаEDS?

    @State private var камера: MapCameraPosition = .automatic

    init(откуда: ТочкаEDS?, куда: ТочкаEDS?, где: ТочкаEDS?) {
        self.откуда = откуда
        self.куда = куда
        self.где = где
    }

    /// Набор точек сменился — карта заново охватывает их все (clcYaFit).
    private var ключ: String {
        (откуда != nil ? "a" : "") + (куда != nil ? "b" : "") + (где != nil ? "c" : "")
    }

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
        Map(position: $камера) {
            if let о = откуда {
                Annotation(EDSText.т("map_from"), coordinate: о.координата) {
                    метка("A")
                }
            }
            if let к = куда {
                Annotation(EDSText.т("map_to"), coordinate: к.координата) {
                    метка("B")
                }
            }
            if let г = где {
                Annotation(EDSText.т("map_courier"), coordinate: г.координата) {
                    Image(systemName: "box.truck.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 34, height: 34)
                        .background(КраскаСделокКабинета.хорошоТекст, in: Circle())
                        .overlay { Circle().strokeBorder(Color.white, lineWidth: 2) }
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .onChange(of: ключ) { _, _ in камера = .automatic }
        .frame(height: 220)
        .clipShape(форма)
        .overlay { форма.strokeBorder(Theme.линия, lineWidth: 1) }
    }

    private func метка(_ буква: String) -> some View {
        Text(буква)
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(Color.white)
            .frame(width: 22, height: 22)
            .background(буква == "A" ? Theme.зелёный2 : КраскаСделокКабинета.синий, in: Circle())
            .overlay { Circle().strokeBorder(Color.white, lineWidth: 2) }
    }
}

// MARK: - Сканер карты (edsCardScan)

/**
 Полный экран камеры: рамка карты 1,586 : 1 с затемнением вокруг, схема карты, бегущая линия, сверху подсказка и
 «Номер читается на самом телефоне…», снизу «Фонарик» (если есть) и «Закрыть». Номер ищется как у сайта (_edsPanFind):
 16–19 цифр, 2–6 в начале, Луна; один и тот же номер дважды — готово.
 */
struct СканерКартыEDS: View {
    let найдено: (String) -> Void
    let закрыть: (String?) -> Void

    @StateObject private var камера = КамераКартыEDS()
    @State private var медленно = false
    @State private var линияВнизу = false

    init(найдено: @escaping (String) -> Void, закрыть: @escaping (String?) -> Void) {
        self.найдено = найдено
        self.закрыть = закрыть
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ПревьюКамерыEDS(сессия: камера.сессия)
                .ignoresSafeArea()
            GeometryReader { гео in
                рамка(гео.size)
            }
            .ignoresSafeArea()
            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Text(EDSText.т(медленно ? "eds_scan_slow" : "eds_scan_hint"))
                        .font(.system(size: 15, weight: .bold))
                        .lineSpacing(2)
                    Text(EDSText.т("eds_scan_priv"))
                        .font(.system(size: 13))
                        .lineSpacing(2)
                        .opacity(0.82)
                }
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                Spacer()
                HStack(spacing: 10) {
                    if камера.естьФонарик {
                        Button {
                            камера.переключитьФонарик()
                        } label: {
                            Label(EDSText.т("eds_scan_torch"), systemImage: камера.фонарик ? "flashlight.on.fill" : "flashlight.off.fill")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Theme.текст)
                                .frame(maxWidth: 260, minHeight: 46)
                                .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                        }
                        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
                    }
                    Button {
                        закрыть(nil)
                    } label: {
                        Text(EDSText.т("eds_scan_close"))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: 260, minHeight: 46)
                            .background(LinearGradient(colors: [Theme.зелёный, Theme.зелёный2], startPoint: .topLeading,
                                                       endPoint: .bottomTrailing),
                                        in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                    }
                    .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .statusBarHidden()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(EDSText.т("eds_scan_t"))
        .task {
            let можно = await камера.запустить()
            if !можно { закрыть(EDSText.т("eds_scan_nocam")) }
        }
        .task {
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            if !Task.isCancelled { медленно = true }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { линияВнизу = true }
        }
        .onDisappear { камера.остановить() }
        .onChange(of: камера.номер) { _, номер in
            guard let номер else { return }
            найдено(номер)
        }
    }

    /// .eds-scan-fr: ширина min(88%, 560), 1,586 : 1, центр на 46% высоты; вокруг — затемнение 0,58.
    private func рамка(_ размер: CGSize) -> some View {
        let ширина = min(размер.width * 0.88, 560)
        let высота = ширина / 1.586
        let центр = CGPoint(x: размер.width / 2, y: размер.height * 0.46)
        let прямоугольник = CGRect(x: центр.x - ширина / 2, y: центр.y - высота / 2, width: ширина, height: высота)
        return ZStack {
            Path { путь in
                путь.addRect(CGRect(origin: .zero, size: размер))
                путь.addRoundedRect(in: прямоугольник, cornerSize: CGSize(width: 12, height: 12))
            }
            .fill(Color.black.opacity(0.58), style: FillStyle(eoFill: true))
            СхемаКартыEDS()
                .frame(width: ширина, height: высота)
                .position(центр)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.92), lineWidth: 2)
                .frame(width: ширина, height: высота)
                .position(центр)
            Capsule()
                .fill(КраскаСделокКабинета.хорошоТекст)
                .shadow(color: КраскаСделокКабинета.хорошоТекст, radius: 6)
                .frame(width: ширина * 0.86, height: 2)
                .position(x: центр.x, y: прямоугольник.minY + высота * (линияВнизу ? 0.76 : 0.28))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// _edsCardSchema: чип, логотип, четыре группы по четыре цифры, срок, имя, круги платёжной системы — светлым контуром.
private struct СхемаКартыEDS: View {
    var body: some View {
        Canvas { контекст, размер in
            let кх = размер.width / 856
            let ку = размер.height / 540
            func п(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
                Path(roundedRect: CGRect(x: x * кх, y: y * ку, width: w * кх, height: h * ку), cornerRadius: r * кх)
            }
            let контур = Color.white.opacity(0.55)
            let линия = StrokeStyle(lineWidth: max(1, 5 * кх))
            контекст.stroke(п(60, 60, 150, 34, 8), with: .color(контур), style: линия)
            контекст.stroke(п(70, 150, 112, 86, 14), with: .color(контур), style: линия)
            for s in 0..<4 {
                for t in 0..<4 {
                    let x = CGFloat(70 + 186 * s + 40 * t)
                    let цифра = п(x, 300, 28, 44, 6)
                    контекст.fill(цифра, with: .color(Color.white.opacity(0.16)))
                    контекст.stroke(цифра, with: .color(Color.white.opacity(0.8)), style: линия)
                }
            }
            контекст.stroke(п(440, 382, 120, 30, 7), with: .color(контур), style: линия)
            контекст.stroke(п(70, 440, 300, 30, 7), with: .color(контур), style: линия)
            let круг1 = Path(ellipseIn: CGRect(x: (706 - 38) * кх, y: (452 - 38) * ку, width: 76 * кх, height: 76 * ку))
            let круг2 = Path(ellipseIn: CGRect(x: (760 - 38) * кх, y: (452 - 38) * ку, width: 76 * кх, height: 76 * ку))
            контекст.stroke(круг1, with: .color(контур), style: линия)
            контекст.stroke(круг2, with: .color(контур), style: линия)
        }
    }
}

/// Камера и распознавание номера. Кадры — на своей очереди; найденный номер и фонарик — на главной.
final class КамераКартыEDS: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    /// Задняя камера есть (_edsCamOk): иначе кнопки сканера нет. Проверяется один раз.
    static let есть: Bool = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil

    let сессия = AVCaptureSession()
    @Published private(set) var номер: String? = nil
    @Published private(set) var естьФонарик = false
    @Published private(set) var фонарик = false

    private let очередь = DispatchQueue(label: "kz.kliko.eds.cardscan")
    private var устройство: AVCaptureDevice? = nil
    /// Дальше — только на очереди кадров.
    private var последний: TimeInterval = 0
    private var попадания: [String: Int] = [:]
    private var готово = false
    private var ориентация: CGImagePropertyOrientation = .right

    /// Разрешение, камера, запуск. false — камеры нет или доступ запрещён.
    @MainActor
    func запустить() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { return false }
        default:
            return false
        }
        guard let камера = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let вход = try? AVCaptureDeviceInput(device: камера) else { return false }
        устройство = камера
        естьФонарик = камера.hasTorch && камера.isTorchAvailable
        let выход = AVCaptureVideoDataOutput()
        выход.alwaysDiscardsLateVideoFrames = true
        выход.setSampleBufferDelegate(self, queue: очередь)
        let ориентацияКадра = Self.ориентацияКадра()
        let сессия = self.сессия
        очередь.async { [weak self] in
            self?.ориентация = ориентацияКадра
            сессия.beginConfiguration()
            if сессия.canSetSessionPreset(.hd1920x1080) { сессия.sessionPreset = .hd1920x1080 }
            if сессия.canAddInput(вход) { сессия.addInput(вход) }
            if сессия.canAddOutput(выход) { сессия.addOutput(выход) }
            сессия.commitConfiguration()
            if let камера = self?.устройство, (try? камера.lockForConfiguration()) != nil {
                if камера.isFocusModeSupported(.continuousAutoFocus) { камера.focusMode = .continuousAutoFocus }
                камера.unlockForConfiguration()
            }
            сессия.startRunning()
        }
        return true
    }

    func остановить() {
        let сессия = self.сессия
        let камера = устройство
        очередь.async { [weak self] in
            self?.готово = true
            if let камера, камера.hasTorch, камера.torchMode == .on, (try? камера.lockForConfiguration()) != nil {
                камера.torchMode = .off
                камера.unlockForConfiguration()
            }
            if сессия.isRunning { сессия.stopRunning() }
        }
    }

    /// _edsScanTorch.
    @MainActor
    func переключитьФонарик() {
        guard let камера = устройство, камера.hasTorch else { return }
        let включить = !фонарик
        guard (try? камера.lockForConfiguration()) != nil else { return }
        камера.torchMode = включить ? .on : .off
        камера.unlockForConfiguration()
        фонарик = включить
    }

    /// Кадр камеры в ориентации экрана (задняя камера: портрет — .right).
    @MainActor
    private static func ориентацияКадра() -> CGImagePropertyOrientation {
        let сцена = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        switch сцена?.interfaceOrientation ?? .portrait {
        case .portraitUpsideDown: return .left
        case .landscapeLeft: return .down
        case .landscapeRight: return .up
        default: return .right
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !готово else { return }
        let сейчас = Date().timeIntervalSince1970
        guard сейчас - последний >= 0.12 else { return }
        последний = сейчас
        let запрос = VNRecognizeTextRequest()
        запрос.recognitionLevel = .accurate
        запрос.usesLanguageCorrection = false
        запрос.recognitionLanguages = ["en-US"]
        запрос.regionOfInterest = CGRect(x: 0, y: 0.18, width: 1, height: 0.64)
        let обработчик = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: ориентация, options: [:])
        guard (try? обработчик.perform([запрос])) != nil else { return }
        let наблюдения = (запрос.results ?? []).sorted { а, б in
            if abs(а.boundingBox.midY - б.boundingBox.midY) > 0.02 { return а.boundingBox.midY > б.boundingBox.midY }
            return а.boundingBox.minX < б.boundingBox.minX
        }
        let строки = наблюдения.compactMap { $0.topCandidates(1).first?.string }
        for номер in ФорматEDS.номераКарт(строки) {
            let раз = (попадания[номер] ?? 0) + 1
            попадания[номер] = раз
            if раз >= 2 {
                готово = true
                DispatchQueue.main.async { [weak self] in
                    self?.номер = номер
                }
                return
            }
        }
    }
}

/// Слой просмотра камеры во весь экран (resizeAspectFill), поворот — по ориентации экрана.
struct ПревьюКамерыEDS: UIViewRepresentable {
    let сессия: AVCaptureSession

    func makeUIView(context: Context) -> ВидПревьюКамерыEDS {
        let вид = ВидПревьюКамерыEDS()
        вид.backgroundColor = .black
        вид.слой?.session = сессия
        вид.слой?.videoGravity = .resizeAspectFill
        return вид
    }

    func updateUIView(_ uiView: ВидПревьюКамерыEDS, context: Context) {}
}

final class ВидПревьюКамерыEDS: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var слой: AVCaptureVideoPreviewLayer? { layer as? AVCaptureVideoPreviewLayer }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let связь = слой?.connection else { return }
        let угол: CGFloat
        switch window?.windowScene?.interfaceOrientation ?? .portrait {
        case .landscapeRight: угол = 0
        case .landscapeLeft: угол = 180
        case .portraitUpsideDown: угол = 270
        default: угол = 90
        }
        if связь.isVideoRotationAngleSupported(угол) { связь.videoRotationAngle = угол }
    }
}
