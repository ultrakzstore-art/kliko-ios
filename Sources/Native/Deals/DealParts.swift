import SwiftUI
import UIKit

/**
 КАРТОЧКА СДЕЛКИ — ОБЩИЕ ДЕТАЛИ (этап 43, владелец 26.09.2026: «всё одно и то же, просто код разный»).

 Кирпичи карточки в краске сайта: плашки .dmn (ok / warn / info / bad), кнопки .dmb (pri / sec / quiet / dgr), текст словаря
 с <b> сайта. 🔴 Кнопка, за которой деньги (этап 44, Config.деньгиСделок = false), помечена стрелкой «наружу» и открывает
 страницу сделки сайта — сам запрос приложение не шлёт.
 */

/// Что нажали на карточке — разбирает ЭкранСделки (у него окна и листы).
enum НажатиеСделки {
    /// Денежное действие — страница сделки сайта (cabinet.php?deal=<id>).
    case наСайт
    case спор
    case чек
    case подтвердитьУсловия
    case отклонитьЗаявку
    case попроситьТалон
    case способ(String)
    case сменитьСпособ
    case способЗаперт
    case маршрут(адрес: String, точка: ТочкаСделки?)
    case курьер(откуда: ТочкаСделки?, куда: ТочкаСделки?)
    case ссылка(URL)
    case скопировать(String)
    case страница(String)
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

// MARK: - Плашка .dmn

enum ВидЗаметкиСделки {
    case хорошо
    case предупреждение
    case инфо
    case плохо
    case серый

    var фон: Color {
        switch self {
        case .хорошо:         return КраскаОбъявлений.хорошоФон
        case .предупреждение: return КраскаОбъявлений.предупреждениеФон
        case .инфо:           return КраскаОбъявлений.инфоФон
        case .плохо:          return КраскаОбъявлений.плохоФон
        case .серый:          return Theme.поверхность2
        }
    }

    var краска: Color {
        switch self {
        case .хорошо:         return КраскаОбъявлений.хорошоТекст
        case .предупреждение: return КраскаОбъявлений.предупреждениеТекст
        case .инфо:           return КраскаОбъявлений.инфоТекст
        case .плохо:          return КраскаОбъявлений.плохоТекст
        case .серый:          return Theme.текст
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
                    .font(.system(size: 14, weight: .semibold))
                    .accessibilityHidden(true)
            }
            текст
                .font(.system(size: 14))
                .multilineTextAlignment(поЦентру ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: поЦентру ? .center : .leading)
        }
        .foregroundStyle(вид.краска)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(вид.фон, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
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
                        .font(.system(size: 15, weight: .semibold))
                        .accessibilityHidden(true)
                }
                Text(надпись)
                    .font(.system(size: 15, weight: .bold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let сумма {
                    Text(сумма)
                        .font(.system(size: 15, weight: .heavy))
                }
                if наСайт {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 13))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(краскаТекста)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(фон, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .overlay {
                if вид == .вторая || вид == .тихая {
                    RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                        .strokeBorder(Theme.линия, lineWidth: 1.5)
                }
            }
            .opacity(доступна ? 1 : 0.5)
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
        .disabled(!доступна)
        .accessibilityHint(наСайт ? СделкиText.т("a11y_site") : "")
    }

    private var фон: AnyShapeStyle {
        switch вид {
        case .главная:
            return AnyShapeStyle(LinearGradient(colors: [Theme.зелёный, Theme.зелёный2], startPoint: .leading,
                                                endPoint: .trailing))
        case .опасная:
            return AnyShapeStyle(КраскаОбъявлений.плохоТекст)
        case .вторая, .тихая:
            return AnyShapeStyle(Theme.поверхность)
        }
    }

    private var краскаТекста: Color {
        switch вид {
        case .главная, .опасная: return Color.white
        case .вторая:            return Theme.текст
        case .тихая:             return Theme.текстВторой
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
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.акцент)
                .accessibilityHidden(true)
            Text(текст)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .fixedSize(horizontal: false, vertical: true)
        }
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
            .font(.system(size: 13))
            .foregroundStyle(Theme.текстВторой)
            .fixedSize(horizontal: false, vertical: true)
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
            .foregroundStyle(вкл ? Theme.звезда : Theme.текстВторой.opacity(0.5))
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
