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
    static func корня() {
        #if DEBUG
        корень += 1
        #endif
    }

    /// Ряд списка ленты построен (ForEach рядов).
    @inline(__always)
    static func ряда() {
        #if DEBUG
        ряды += 1
        #endif
    }

    /// Посчитано тело карточки ленты (ListingCard.body).
    @inline(__always)
    static func карточки() {
        #if DEBUG
        карточки += 1
        #endif
    }

    #if DEBUG
    static func сбросить() {
        корень = 0
        ряды = 0
        карточки = 0
    }
    #endif
}

#if DEBUG
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
        Self.строка(String(format: "scroll start: содержимое %.0f pt, окно %.0f pt", прокрутка.contentSize.height,
                           прокрутка.bounds.height))
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
