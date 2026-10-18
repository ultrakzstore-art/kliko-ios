import SwiftUI
import UIKit

/**
 ЗАМЕР ЛИСТАНИЯ В CI (владелец 17.10.2026: «почему при скроллинге будто тяжело смартфону, нет ощущения лёгкости — как
 будто тяжёлое приложение»). Только отладочная сборка и только с аргументом запуска -klikoScrollBench YES: через 10 с
 после того, как список главной подключился (НаблюдательСпискаЛенты, FeedList.swift), лента сама листается 16 с — вниз и
 вверх, от верха главной до низа ленты, по 4 с на скорость 1500, 2500, 4000 и 2500 pt/с, — как пальцем, только ровно.
 Каждый кадр — шаг времени между кадрами: подвисание — шаг больше полутора периодов экрана.

 В stderr — строки «[kliko-perf] scroll …» по каждой скорости и итог, вместе со счётчиками СчётБенча: сколько раз за время
 замера считались корень ленты (списокЛенты), ряды списка и карточки (ListingCard.body). Карточек должно быть порядка
 того, сколько их выехало на экран, а не кадров; корень — единицы раз: больше — ленту перерисовывает что-то, кроме самой
 прокрутки. Job perf (ios-check.yml) в это же время снимает Time Profiler. В выпускной сборке не делает ничего.

 Сравнение (verify, ios-check.yml): тот же замер с аргументами — -klikoBenchNoPhotos YES (фото карточек не грузятся,
 заглушка), -klikoBenchPlain YES (вместо ячейки ленты — простая карточка: серый прямоугольник 4:3 и три строки текста,
 без сердца, «Поделиться», меню, зума и меток), -klikoBenchSingleTop YES (верх главной одной строкой, как до 87) и
 -klikoBenchBare YES (ни верха, ни карточек — потолок самого симулятора). 17.10.2026: без фото — почти как есть (242
 кадра против 220 из ~960), простые ячейки — 376: фото не главное, карточка — заметная часть, а больше всего — верх
 главной одной строкой.
 */
@MainActor
enum СчётБенча {
    #if DEBUG
    static var корень = 0
    static var ряды = 0
    static var карточки = 0
    #endif

    /// Корень ленты построил список (NativeFeedView.списокЛенты).
    @inline(__always)
    static func плюсКорень() {
        #if DEBUG
        корень += 1
        #endif
    }

    /// Ряд списка ленты построен (ForEach рядов).
    @inline(__always)
    static func плюсРяд() {
        #if DEBUG
        ряды += 1
        #endif
    }

    /// Посчитано тело карточки ленты (ListingCard.body).
    @inline(__always)
    static func плюсКарточка() {
        #if DEBUG
        карточки += 1
        #endif
    }

    /// Сравнение (17.10.2026, после «простые ячейки — 626 кадров, как есть — 269»): что в ячейке ленты стоит кадров.
    /// Обвязка — сердце, «Поделиться», меню долгого нажатия, отчёт ТОП и источник зума; меню и зум — по отдельности. В
    /// выпускной сборке всегда false (флаг).
    static let безОбвязки = флаг("klikoBenchNoWrap")
    static let безМеню = флаг("klikoBenchNoMenu")
    static let безЗума = флаг("klikoBenchNoZoom")
    /// Второй круг (обвязка почти ничего не стоит: -O как есть 277, без обвязки 273, простые ячейки 595): что внутри
    /// карточки сетки — цена, строка фактов, подвал, вид фото (КартинкаЛенты с подложкой), рамка (обводки, тень, голос).
    static let безЦены = флаг("klikoBenchNoPrice")
    static let безФактов = флаг("klikoBenchNoFacts")
    static let безПодвала = флаг("klikoBenchNoFooter")
    static let безФотоВида = флаг("klikoBenchNoPhotoView")
    static let безРамки = флаг("klikoBenchNoFrame")
    /// Третий круг (второй: без рамки 482, без вида фото 383, как есть 261 — отладка): рамка слоями (CardChrome.swift)
    /// против прежней SwiftUI, без обрезки по скруглению, фото без подготовки к показу (preparingForDisplay). Итог
    /// третьего: рамка слоями 259, прежняя 258, без обрезки 523 — дорогая именно обрезка всей карточки; с четвёртого
    /// «без обрезки» — прямоугольная обрезка фото вместо скруглённой.
    static let прежняяРамка = флаг("klikoBenchOldFrame")
    static let безОбрезки = флаг("klikoBenchNoClip")

    /// Аргумент запуска замера; в выпускной сборке — всегда false.
    private static func флаг(_ ключ: String) -> Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: ключ)
        #else
        return false
        #endif
    }

    #if DEBUG
    /// Сравнение: фото карточек не грузить (КартинкаЛенты показывает заглушку).
    static let безФото = UserDefaults.standard.bool(forKey: "klikoBenchNoPhotos")
    /// Сравнение: ни верха главной, ни карточек — серый блок 2400 pt и простые ячейки (потолок симулятора CI).
    static let голый = UserDefaults.standard.bool(forKey: "klikoBenchBare")
    /// Сравнение: вместо ячейки ленты — простая карточка (ПростаяЯчейкаБенча).
    static let простыеЯчейки = голый || UserDefaults.standard.bool(forKey: "klikoBenchPlain")
    /// Сравнение: верх главной одной строкой списка, как до сборки 87 (Config.верхГлавнойСтроками).
    static let верхОднойСтрокой = UserDefaults.standard.bool(forKey: "klikoBenchSingleTop")

    static func сбросить() {
        корень = 0
        ряды = 0
        карточки = 0
    }
    #endif
}

extension View {
    /// Модификаторы ячейки, которые замер листания умеет выключать для сравнения (СчётБенча.безОбвязки, безМеню). В
    /// выпускной сборке — просто применить, без лишней ветки в дереве.
    #if DEBUG
    @ViewBuilder
    func кромеЗамера<V: View>(_ выключить: Bool, _ применить: (Self) -> V) -> some View {
        if выключить {
            self
        } else {
            применить(self)
        }
    }
    #else
    @inline(__always)
    func кромеЗамера<V: View>(_ выключить: Bool, _ применить: (Self) -> V) -> V {
        применить(self)
    }
    #endif

    /// Замер листания: вместо части карточки — пустое место примерно той же высоты (СчётБенча.безЦены и др.). В
    /// выпускной сборке — сам вид.
    #if DEBUG
    @ViewBuilder
    func заменаЗамера(_ выключить: Bool, высота: CGFloat) -> some View {
        if выключить {
            Color.clear.frame(height: высота)
        } else {
            self
        }
    }
    #else
    @inline(__always)
    func заменаЗамера(_ выключить: Bool, высота: CGFloat) -> Self {
        self
    }
    #endif
}

#if DEBUG
/// Простая ячейка для сравнения (-klikoBenchPlain): примерно того же размера, что карточка сетки, без всего остального.
struct ПростаяЯчейкаБенча: View {
    let товар: Listing

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle()
                .fill(Color.gray.opacity(0.18))
                .aspectRatio(4 / 3, contentMode: .fit)
            Text(ListingCard.цена(товар))
                .font(.system(size: 19, weight: .bold))
                .padding(.horizontal, 12)
            Text(товар.title)
                .font(.system(size: 13))
                .lineLimit(2, reservesSpace: true)
                .padding(.horizontal, 12)
            Text(товар.city.isEmpty ? " " : товар.city)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

@MainActor
final class БенчЛистания: NSObject {
    static let shared = БенчЛистания()

    /// Скорости по очереди, pt/с, по наСкорость секунд каждая.
    private static let скорости: [CGFloat] = [1500, 2500, 4000, 2500]
    private static let наСкорость: CFTimeInterval = 4
    /// Через столько секунд после подключения списка — начать: главная успевает загрузить ряды и первые фото.
    private static let ждать: TimeInterval = 10

    private var был = false
    private weak var прокрутка: UIScrollView?
    private var ссылка: CADisplayLink?
    private var начало: CFTimeInterval = 0
    private var прошлый: CFTimeInterval = 0
    /// Самый короткий период экрана за замер — по нему норма шага (60 или 120 Гц).
    private var период: CFTimeInterval = 0
    private var знак: CGFloat = 1
    private var номер = 0
    private var этап = Счёт()
    private var всего = Счёт()

    private struct Счёт {
        var кадров = 0
        var подвисаний = 0
        var худший: CFTimeInterval = 0
        var потеряно: CFTimeInterval = 0

        mutating func шаг(_ шаг: CFTimeInterval, норма: CFTimeInterval) {
            кадров += 1
            if шаг > худший { худший = шаг }
            if норма > 0 && шаг > норма * 1.5 {
                подвисаний += 1
                потеряно += шаг - норма
            }
        }

        func строка() -> String {
            let доля: Double = кадров > 0 ? Double(подвисаний) * 100 / Double(кадров) : 0
            return String(format: "кадров %ld, подвисаний %ld (%.1f%%), худший %.0f мс, потеряно %.0f мс",
                          кадров, подвисаний, доля, худший * 1000, потеряно * 1000)
        }
    }

    private override init() {
        super.init()
    }

    /// Список ленты подключился (НаблюдательСпискаЛенты.подключить). Замер — один за запуск, только на главной.
    func может(_ прокрутка: UIScrollView, где: String) {
        guard !был, где == "home", UserDefaults.standard.bool(forKey: "klikoScrollBench") else { return }
        был = true
        self.прокрутка = прокрутка
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.ждать * 1_000_000_000))
            self?.пуск()
        }
    }

    private func пуск() {
        guard let прокрутка, прокрутка.window != nil else {
            Self.строка("scroll: списка нет на экране — замера нет")
            return
        }
        let вариант: String = [СчётБенча.голый ? "голый" : "", СчётБенча.простыеЯчейки ? "простые ячейки" : "",
                               СчётБенча.безФото ? "без фото" : "", СчётБенча.верхОднойСтрокой ? "верх одной строкой" : "",
                               СчётБенча.безОбвязки ? "без обвязки" : "", СчётБенча.безМеню ? "без меню" : "",
                               СчётБенча.безЗума ? "без зума" : "", СчётБенча.безЦены ? "без цены" : "",
                               СчётБенча.безФактов ? "без фактов" : "", СчётБенча.безПодвала ? "без подвала" : "",
                               СчётБенча.безФотоВида ? "без вида фото" : "", СчётБенча.безРамки ? "без рамки" : "",
                               СчётБенча.прежняяРамка ? "прежняя рамка" : "", СчётБенча.безОбрезки ? "без обрезки" : "",
                               UserDefaults.standard.bool(forKey: "klikoBenchNoPrepare") ? "фото без подготовки" : ""]
            .filter { !$0.isEmpty }.joined(separator: ", ")
        Self.строка(String(format: "scroll start (%@): содержимое %.0f pt, окно %.0f pt", вариант.isEmpty ? "как есть" : вариант,
                           прокрутка.contentSize.height, прокрутка.bounds.height))
        СчётБенча.сбросить()
        let новая = CADisplayLink(target: self, selector: #selector(кадр(_:)))
        новая.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        новая.add(to: .main, forMode: .common)
        ссылка = новая
    }

    @objc(klikoScrollBenchFrame:)
    private func кадр(_ с: CADisplayLink) {
        guard let прокрутка else {
            стоп()
            return
        }
        let сейчас: CFTimeInterval = с.timestamp
        var п: CFTimeInterval = с.targetTimestamp - с.timestamp
        if п <= 0 { п = с.duration }
        if начало == 0 {
            начало = сейчас
            прошлый = сейчас
            период = п
            return
        }
        let шаг: CFTimeInterval = сейчас - прошлый
        прошлый = сейчас
        if п > 0 { период = min(период, п) }
        let индекс = Int((сейчас - начало) / Self.наСкорость)
        if индекс != номер {
            отчёт(номер)
            номер = индекс
            этап = Счёт()
        }
        guard индекс < Self.скорости.count else {
            стоп()
            return
        }
        этап.шаг(шаг, норма: период)
        всего.шаг(шаг, норма: период)
        let верх: CGFloat = -прокрутка.adjustedContentInset.top
        let низ: CGFloat = max(верх, прокрутка.contentSize.height - прокрутка.bounds.height
                                     + прокрутка.adjustedContentInset.bottom)
        var y: CGFloat = прокрутка.contentOffset.y + знак * Self.скорости[индекс] * CGFloat(min(шаг, 0.1))
        if y >= низ {
            y = низ
            знак = -1
        } else if y <= верх {
            y = верх
            знак = 1
        }
        прокрутка.setContentOffset(CGPoint(x: прокрутка.contentOffset.x, y: y), animated: false)
    }

    private func отчёт(_ индекс: Int) {
        guard индекс < Self.скорости.count else { return }
        Self.строка(String(format: "scroll %.0f pt/с: ", Self.скорости[индекс]) + этап.строка())
    }

    private func стоп() {
        ссылка?.invalidate()
        ссылка = nil
        let герц: Double = период > 0 ? (1 / период).rounded() : 0
        Self.строка("scroll total: " + всего.строка() + String(format: ", экран %.0f Гц", герц))
        Self.строка("scroll counts: корень ленты \(СчётБенча.корень), рядов \(СчётБенча.ряды), карточек \(СчётБенча.карточки)")
        ДымоваяПроверка.отметить("scroll-bench-done")
    }

    private static func строка(_ текст: String) {
        FileHandle.standardError.write(Data(("[kliko-perf] " + текст + "\n").utf8))
    }
}
#endif
