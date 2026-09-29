import SwiftUI
import UIKit

/**
 КАРТОЧКА СДЕЛКИ — ОБЩИЕ ДЕТАЛИ (этап 43, владелец 26.09.2026: «всё одно и то же, просто код разный»).

 Кирпичи карточки в краске сайта: плашки .dmn (ok / warn / info / bad), кнопки .dmb (pri / sec / quiet / dgr), текст словаря
 с <b> сайта. Денежные кнопки ведут в свои окна (ДеньгиСделкиМодель), передача — в свои блоки (ПередачаСделкиМодель):
 страницы сделки сайта у карточки нет.
 */

/// Что нажали на карточке — разбирает ЭкранСделки (у него окна и листы).
enum НажатиеСделки {
    /// Этап 44: денежная кнопка — окна ДеньгиСделкиМодель.
    case деньги(ДействиеДенегСделки)
    case спор
    case чек
    case подтвердитьУсловия
    case отклонитьЗаявку
    case попроситьТалон
    /// Продавец подписывает гарантийный талон (warranty_sign; need_otp — своё окно eGov).
    case подписатьТалон
    /// «Не согласен с причиной — к модератору» (clocalReturnDispute): спор return_fault после вопроса.
    case спорВозврата
    case способ(String)
    case сменитьСпособ
    case способЗаперт
    case маршрут(адрес: String, точка: ТочкаСделки?)
    /// Точка забора (откуда: true) или доставки на карте — своё окно ЛистТочкиСделки (set_pickup).
    case точка(откуда: Bool)
    case курьер(откуда: ТочкаСделки?, куда: ТочкаСделки?)
    case ссылка(URL)
    /// «Где курьер» / «Отследить»: своя карточка «Отслеживание» листом (Sources/Native/Tracking), без сайта.
    case отслеживание
    case скопировать(String)
    case страница(String)
}

/// Этап 44: стрелка «наружу» у денежной кнопки. Сайт карточка больше не открывает (стоп-кран — своё окно «шаг пока
/// недоступен», ЭкранСделки.нажато), поэтому стрелки и подсказки VoiceOver «Откроется страница на сайте» нет.
enum ДеньгиКнопок {
    static var наСайте: Bool { false }
}

// MARK: - Текст словаря с <b>

enum ТекстСделки {
    /**
     Текст словаря сайта как есть, с <b>…</b> (dl_dep_banner, dl_shipped_seller, dl_returned_to_you…): жирное — жирным,
     <br> — перевод строки, прочие теги — прочь. Слова не меняются.
     */
    static func сЖирным(_ сырой: String) -> Text {
        var s = сырой.replacingOccurrences(of: "<br>", with: "\n").replacingOccurrences(of: "<br/>", with: "\n")
        s = s.replacingOccurrences(of: "&nbsp;", with: "\u{00A0}")
        var итог = Text("")
        var жирный = false
        var остаток = Substring(s)
        while !остаток.isEmpty {
            let метка = жирный ? "</b>" : "<b>"
            if let r = остаток.range(of: метка) {
                let кусок = безТегов(String(остаток[остаток.startIndex..<r.lowerBound]))
                итог = итог + (жирный ? Text(кусок).bold() : Text(кусок))
                остаток = остаток[r.upperBound...]
                жирный.toggle()
            } else {
                let кусок = безТегов(String(остаток))
                итог = итог + (жирный ? Text(кусок).bold() : Text(кусок))
                break
            }
        }
        return итог
    }

    private static func безТегов(_ s: String) -> String {
        s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    /// Тот же текст без разметки — для VoiceOver, копирования и печати.
    static func чистый(_ сырой: String) -> String {
        сырой.replacingOccurrences(of: "<br>", with: " ").replacingOccurrences(of: "<[^>]+>", with: "",
                                                                            options: .regularExpression)
    }
}

// MARK: - Краски кабинета (--tint-* / --on-* / --edge-* из css_cabinet.css)

/// Статусные краски сделок и кошелька — значения :root и [data-theme=dark] css_cabinet.css (не краски «Моих объявлений»).
enum КраскаСделокКабинета {
    static let хорошоФон = Theme.цвет(светлый: Theme.hex(0xE7F6EE), тёмный: Theme.hex(0x34C997, 0.14))
    static let хорошоТекст = Theme.цвет(0x0F7A44, 0x5CD39A)
    static let хорошоКромка = Theme.цвет(светлый: Theme.hex(0xCDEBD7), тёмный: Theme.hex(0x34C997, 0.32))
    static let предупреждениеФон = Theme.цвет(светлый: Theme.hex(0xFFF4E5), тёмный: Theme.hex(0xE0BD5E, 0.15))
    static let предупреждениеТекст = Theme.цвет(0x92400E, 0xE0BD5E)
    static let предупреждениеКромка = Theme.цвет(светлый: Theme.hex(0xFDE68A), тёмный: Theme.hex(0xE0BD5E, 0.34))
    static let инфоФон = Theme.цвет(светлый: Theme.hex(0xEEF4FF), тёмный: Theme.hex(0x60A5FA, 0.15))
    static let инфоТекст = Theme.цвет(0x1E40AF, 0x7CB8F5)
    static let инфоКромка = Theme.цвет(светлый: Theme.hex(0xC7D6F5), тёмный: Theme.hex(0x60A5FA, 0.34))
    static let плохоФон = Theme.цвет(светлый: Theme.hex(0xFEE2E2), тёмный: Theme.hex(0xFF6168, 0.15))
    static let плохоТекст = Theme.цвет(0x991B1B, 0xFF8A8F)
    static let плохоКромка = Theme.цвет(светлый: Theme.hex(0xFECACA), тёмный: Theme.hex(0xFF6168, 0.34))
    static let арендаФон = Theme.цвет(светлый: Theme.hex(0xEAF0FF), тёмный: Theme.hex(0x60A5FA, 0.16))
    static let арендаТекст = Theme.цвет(0x1D4ED8, 0x8AB4F8)
    static let арендаКромка = Theme.цвет(светлый: Theme.hex(0xC3D4FB), тёмный: Theme.hex(0x60A5FA, 0.36))
    /// --on-ai: ссылка «→ сделка» в баллах.
    static let иИТекст = Theme.цвет(0x6C3FC5, 0xB79BF5)
    /// --acc-on кабинета: #0f5132 и #5cd39a.
    static let акцент = Theme.цвет(0x0F5132, 0x5CD39A)
    /// #1a56db renderDeal: «Итого к оплате» и точки истории — одна краска в обеих темах.
    static let синий = Color(uiColor: Theme.hex(0x1A56DB))
    /// Тень зелёных кнопок: rgba(52,201,151,.55) под 0 6px 14px -7px.
    static let теньКнопки = Color(red: 52 / 255, green: 201 / 255, blue: 151 / 255).opacity(0.45)
}

// MARK: - Плашка .dmn

enum ВидЗаметкиСделки {
    case хорошо
    case предупреждение
    case инфо
    case плохо
    case серый

    var фон: Color {
        switch self {
        case .хорошо:         return КраскаСделокКабинета.хорошоФон
        case .предупреждение: return КраскаСделокКабинета.предупреждениеФон
        case .инфо:           return КраскаСделокКабинета.инфоФон
        case .плохо:          return КраскаСделокКабинета.плохоФон
        case .серый:          return Theme.поверхность2
        }
    }

    var краска: Color {
        switch self {
        case .хорошо:         return КраскаСделокКабинета.хорошоТекст
        case .предупреждение: return КраскаСделокКабинета.предупреждениеТекст
        case .инфо:           return КраскаСделокКабинета.инфоТекст
        case .плохо:          return КраскаСделокКабинета.плохоТекст
        case .серый:          return Theme.текст
        }
    }

    var кромка: Color {
        switch self {
        case .хорошо:         return КраскаСделокКабинета.хорошоКромка
        case .предупреждение: return КраскаСделокКабинета.предупреждениеКромка
        case .инфо:           return КраскаСделокКабинета.инфоКромка
        case .плохо:          return КраскаСделокКабинета.плохоКромка
        case .серый:          return Theme.линия
        }
    }
}

struct ЗаметкаСделки: View {
    let текст: Text
    let вид: ВидЗаметкиСделки
    var символ: String? = nil
    var поЦентру = false

    init(_ текст: Text, вид: ВидЗаметкиСделки, символ: String? = nil, поЦентру: Bool = false) {
        self.текст = текст
        self.вид = вид
        self.символ = символ
        self.поЦентру = поЦентру
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let символ, !поЦентру {
                Image(systemName: символ)
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityHidden(true)
            }
            текст
                .font(.system(size: 13))
                .lineSpacing(3)
                .multilineTextAlignment(поЦентру ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: поЦентру ? .center : .leading)
        }
        .foregroundStyle(вид.краска)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(вид.фон, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                .strokeBorder(вид.кромка, lineWidth: 1.5)
        }
    }
}

// MARK: - Кнопка .dmb

struct КнопкаСделки: View {
    enum Вид {
        case главная
        case вторая
        case тихая
        case опасная
    }

    let надпись: String
    let вид: Вид
    var символ: String? = nil
    var сумма: String? = nil
    /// Деньги — страница сайта: стрелка «наружу».
    var наСайт = false
    var доступна = true
    let действие: () -> Void

    init(_ надпись: String, вид: Вид, символ: String? = nil, сумма: String? = nil, наСайт: Bool = false,
         доступна: Bool = true, действие: @escaping () -> Void) {
        self.надпись = надпись
        self.вид = вид
        self.символ = символ
        self.сумма = сумма
        self.наСайт = наСайт
        self.доступна = доступна
        self.действие = действие
    }

    var body: some View {
        Button(action: действие) {
            HStack(spacing: 8) {
                if let символ {
                    Image(systemName: символ)
                        .font(.system(size: 16))
                        .accessibilityHidden(true)
                }
                Text(надпись)
                    .font(.system(size: размерШрифта, weight: вид == .тихая ? .semibold : .bold))
                    .lineSpacing(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let сумма {
                    Text(сумма)
                        .font(.system(size: размерШрифта, weight: .heavy))
                }
                if наСайт {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 13))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(краскаТекста)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: высота)
            .background(фон, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .overlay {
                if let рамка {
                    RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                        .strokeBorder(рамка, lineWidth: 1.5)
                }
            }
            .shadow(color: вид == .главная ? КраскаСделокКабинета.теньКнопки : .clear, radius: 4, x: 0, y: 5)
            .opacity(доступна ? 1 : 0.55)
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
        .disabled(!доступна)
        .accessibilityHint(наСайт ? СделкиText.т("a11y_site") : "")
    }

    /// .dmb 14px, .pri 15px, .quiet 13px.
    private var размерШрифта: CGFloat {
        switch вид {
        case .главная:           return 15
        case .вторая, .опасная:  return 14
        case .тихая:             return 13
        }
    }

    /// .pri — padding 14, .dmb — 12, .quiet — 10.
    private var высота: CGFloat {
        switch вид {
        case .главная:           return 50
        case .вторая, .опасная:  return 44
        case .тихая:             return 38
        }
    }

    private var фон: AnyShapeStyle {
        switch вид {
        case .главная:
            return AnyShapeStyle(LinearGradient(colors: [Theme.зелёный, Theme.зелёный2], startPoint: .topLeading,
                                                endPoint: .bottomTrailing))
        case .опасная:
            return AnyShapeStyle(КраскаСделокКабинета.плохоФон)
        case .вторая:
            return AnyShapeStyle(Theme.поверхность2)
        case .тихая:
            return AnyShapeStyle(Color.clear)
        }
    }

    private var рамка: Color? {
        switch вид {
        case .вторая:            return Theme.линия
        case .опасная:           return КраскаСделокКабинета.плохоКромка
        case .главная, .тихая:   return nil
        }
    }

    private var краскаТекста: Color {
        switch вид {
        case .главная:  return Color.white
        case .опасная:  return КраскаСделокКабинета.плохоТекст
        case .вторая:   return Theme.текст
        case .тихая:    return Theme.текстВторой
        }
    }
}

/// Блок на поверхности (.clc, «Деньги и документы»).
struct БлокСделки<Содержимое: View>: View {
    let содержимое: Содержимое

    init(@ViewBuilder _ содержимое: () -> Содержимое) {
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
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
    }
}

/// Заголовок блока с символом (.clc-h).
struct ЗаголовокБлокаСделки: View {
    let текст: String
    let символ: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: символ)
                .font(.system(size: 17, weight: .regular))
                .accessibilityHidden(true)
            Text(текст)
                .font(.system(size: 14, weight: .heavy))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(КраскаСделокКабинета.хорошоТекст)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Мелкий серый текст (.clc-sub).
struct ПодписьСделки: View {
    let текст: String

    init(_ текст: String) {
        self.текст = текст
    }

    var body: some View {
        Text(текст)
            .font(.system(size: 12))
            .lineSpacing(2)
            .foregroundStyle(Theme.текстВторой)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Свёрнутый блок (.dmf, dmFold)

/// .dmf: рамка 1.5 --line, радиус 12; шапка — значок 32×32 на --tint-ok, заголовок 14/700, стрелка вниз (открыт — вверх),
/// под открытой шапкой черта 1.5; тело — поля 12/14/14.
struct СвёрткаСделки<Содержимое: View>: View {
    let заголовок: String
    let символ: String
    @Binding var открыт: Bool
    let содержимое: Содержимое

    init(заголовок: String, символ: String, открыт: Binding<Bool>, @ViewBuilder _ содержимое: () -> Содержимое) {
        self.заголовок = заголовок
        self.символ = символ
        self._открыт = открыт
        self.содержимое = содержимое()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                открыт.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: символ)
                        .font(.system(size: 16))
                        .foregroundStyle(КраскаСделокКабинета.хорошоТекст)
                        .frame(width: 32, height: 32)
                        .background(КраскаСделокКабинета.хорошоФон,
                                    in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                        .accessibilityHidden(true)
                    Text(заголовок)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.текст)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.текстВторой)
                        .rotationEffect(.degrees(открыт ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            if открыт {
                Rectangle()
                    .fill(Theme.линия)
                    .frame(height: 1.5)
                    .accessibilityHidden(true)
                содержимое
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1.5)
        }
    }
}

// MARK: - Звёзды

/// Звёзды оценки: только показ (dealStarsRO) или выбор (dealSetRating).
struct ЗвёздыСделки: View {
    let звёзд: Int
    var размер: CGFloat = 26
    var выбрать: ((Int) -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { n in
                звезда(n)
            }
        }
        .accessibilityElement(children: выбрать == nil ? .ignore : .contain)
        .accessibilityLabel(String(format: СделкиText.т("a11y_stars"), звёзд))
    }

    @ViewBuilder
    private func звезда(_ n: Int) -> some View {
        let вкл = n <= звёзд
        let картинка = Image(systemName: вкл ? "star.fill" : "star")
            .font(.system(size: размер))
            .foregroundStyle(Color(uiColor: Theme.hex(вкл ? 0xF0A91E : 0xE4EAE7)))
        if let выбрать {
            Button {
                выбрать(n)
            } label: {
                картинка
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(format: СделкиText.т("a11y_stars"), n))
            .accessibilityAddTraits(вкл ? .isSelected : [])
        } else {
            картинка
        }
    }
}

// MARK: - Ссылки на навигаторы (hovRoutePick, hovCourierPick, dealCarNavHtml)

enum НавигаторыСделки {
    private static let метка = "&ref=klikokz&lang=ru&appmetrica_tracking_id=25395763362139037"

    /// Число как в JS-строке сайта («43.238949»).
    static func ч(_ n: Double) -> String { String(n) }

    /// Шесть знаков после точки (toFixed(6) в dealCarNavHtml).
    static func точка(_ n: Double) -> String { String(format: "%.6f", n) }

    /// Адрес из кусков: без длинных цепочек «+», которые дорого стоят проверке типов.
    private static func адрес(_ части: [String]) -> URL? { URL(string: части.joined()) }

    /// Яндекс Go — такси к точке.
    static func такси(_ к: ТочкаСделки) -> URL? {
        адрес(["https://3.redirect.appmetrica.yandex.com/route?end-lat=", ч(к.широта), "&end-lon=", ч(к.долгота), метка])
    }

    /// 2ГИС — маршрут к точке; без точки — поиск по адресу.
    static func дваГис(_ к: ТочкаСделки?, адрес строка: String) -> URL? {
        if let к {
            return адрес(["https://2gis.kz/directions/points/%7C", ч(к.долгота), "%2C", ч(к.широта)])
        }
        let запрос = строка.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        return запрос.isEmpty ? nil : адрес(["https://2gis.kz/search/", запрос])
    }

    /// Яндекс Go — курьер между двумя точками (tariffClass=courier).
    static func курьерЯндекса(_ а: ТочкаСделки, _ б: ТочкаСделки) -> URL? {
        адрес(["https://3.redirect.appmetrica.yandex.com/route?start-lat=", ч(а.широта), "&start-lon=", ч(а.долгота),
               "&end-lat=", ч(б.широта), "&end-lon=", ч(б.долгота), "&tariffClass=courier", метка])
    }

    /// 2ГИС — такси по тем же точкам (курьерского тарифа у 2ГИС нет).
    static func таксиДваГис(_ а: ТочкаСделки, _ б: ТочкаСделки) -> URL? {
        адрес(["https://2gis.kz/directions/tab/taxi/points/", ч(а.долгота), ",", ч(а.широта), "%7C", ч(б.долгота), ",",
               ч(б.широта)])
    }

    /// dealCarNavHtml: 2ГИС и такси к пункту с шестью знаками после точки.
    static func маршрутКПункту(_ к: ТочкаСделки) -> URL? {
        адрес(["https://2gis.kz/directions/points/%7C", точка(к.долгота), "%2C", точка(к.широта)])
    }

    static func таксиКПункту(_ к: ТочкаСделки) -> URL? {
        адрес(["https://3.redirect.appmetrica.yandex.com/route?end-lat=", точка(к.широта), "&end-lon=", точка(к.долгота),
               "&appmetrica_tracking_id=25395763362139037&lang=ru&ref=klikokz"])
    }
}
