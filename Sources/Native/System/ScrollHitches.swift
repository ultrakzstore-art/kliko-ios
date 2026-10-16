import SwiftUI
import UIKit

/**
 ПОДВИСАНИЯ ПРИ ЛИСТАНИИ ЛЕНТЫ (владелец 16.10.2026: «при листании витрины может подвисать»).

 Пока человек листает ленту или витрину главной — от касания до конца инерции, — CADisplayLink сверяет каждый кадр с
 ожидаемым периодом: шаг дольше полутора периодов — подвисание, всё сверх периода у таких кадров — «потерянное» время.
 Период берётся у самого CADisplayLink (targetTimestamp минус timestamp, запасной — duration): у ProMotion он свой —
 8,3 мс на 120 Гц, 16,7 мс на 60 Гц, — так кадр 120 Гц не считается долгим по мерке 60 Гц и наоборот. Лента встала —
 одно событие feed_scroll в ЗамерыСкорости (ЗамерыСкорости.листание): кадров, подвисаний, худший кадр в мс, доля
 потерянного, длительность, частота и где листали; модель iPhone — у пачки, лёгкий режим событие получает там же, как
 все замеры.

 Ноль работы, когда не листают: счётчик заводится началом жеста прокрутки (цель у её panGestureRecognizer — её зовут
 только касания) и останавливается вместе с лентой; рубильник замеров выключен (Config.телеметрияСкорости) или
 дневной предел feed_scroll уже выбран (ЗамерыСкорости.нуженЗамер) — не заводится вовсе. Никаких данных о человеке —
 только время кадров.
 */
@MainActor
final class ЗамерЛистания: NSObject {
    static let shared = ЗамерЛистания()

    /// Меньше стольких кадров — не листание, а случайное касание: события нет.
    private static let меньшеКадров = 10
    /// Дольше — замер кончается и уходит; следующее касание начнёт новый.
    private static let дольшеСекунд: CFTimeInterval = 30
    /// Столько кадров подряд без пальца и без инерции — лента встала.
    private static let тихихДоКонца = 3

    private var ссылка: CADisplayLink?
    private weak var прокрутка: UIScrollView?
    private var где = ""
    /// Время прошлого кадра (timestamp); 0 — кадров ещё не было.
    private var прошлый: CFTimeInterval = 0
    /// Ожидаемый период после прошлого кадра — по нему меряется следующий шаг.
    private var прошлыйПериод: CFTimeInterval = 0
    /// Прошлый кадр лента ещё двигалась (палец или инерция): шаг после него — листание.
    private var двигалась = false
    private var тихих = 0
    private var кадров = 0
    private var подвисаний = 0
    private var худший: CFTimeInterval = 0
    private var потеряно: CFTimeInterval = 0
    private var длилось: CFTimeInterval = 0
    /// Самый короткий из ожидаемых периодов — по нему частота замера (60 или 120 Гц).
    private var кратчайший: CFTimeInterval = 0

    /// Палец лёг на ленту. Замер уже идёт (новый толчок во время инерции) — продолжается тот же.
    func начать(_ прокрутка: UIScrollView, где: String) {
        guard ссылка == nil, ЗамерыСкорости.нуженЗамер("feed_scroll"),
              UIApplication.shared.applicationState == .active else { return }
        self.прокрутка = прокрутка
        self.где = где
        прошлый = 0
        прошлыйПериод = 0
        двигалась = true
        тихих = 0
        кадров = 0
        подвисаний = 0
        худший = 0
        потеряно = 0
        длилось = 0
        кратчайший = 0
        /* Ушли из приложения посреди листания — замер без события: первый кадр после возврата был бы «подвисанием»
           длиной во всё время в фоне. */
        NotificationCenter.default.addObserver(self, selector: #selector(ушлиИзПриложения(_:)),
                                               name: UIApplication.willResignActiveNotification, object: nil)
        let новая = CADisplayLink(target: self, selector: #selector(кадр(_:)))
        новая.add(to: .main, forMode: .common)
        ссылка = новая
    }

    @objc(klikoFeedScrollFrame:)
    private func кадр(_ с: CADisplayLink) {
        let сейчас = с.timestamp
        var период = с.targetTimestamp - с.timestamp
        if период <= 0 { период = с.duration }
        if прошлый > 0 && двигалась {
            let шаг = сейчас - прошлый
            let норма = прошлыйПериод > 0 ? прошлыйПериод : период
            кадров += 1
            длилось += шаг
            if шаг > худший { худший = шаг }
            if норма > 0 && шаг > норма * 1.5 {
                подвисаний += 1
                потеряно += шаг - норма
            }
        }
        прошлый = сейчас
        if период > 0 {
            прошлыйПериод = период
            if кратчайший == 0 || период < кратчайший { кратчайший = период }
        }
        guard let прокрутка, прокрутка.window != nil else {
            остановить(отправить: false)          // лента ушла с экрана (другая вкладка, экран поверх)
            return
        }
        двигалась = прокрутка.isTracking || прокрутка.isDragging || прокрутка.isDecelerating
        тихих = двигалась ? 0 : тихих + 1
        if тихих >= Self.тихихДоКонца || длилось > Self.дольшеСекунд {
            остановить(отправить: true)
        }
    }

    @objc(klikoFeedScrollResign:)
    private func ушлиИзПриложения(_ уведомление: Notification) {
        остановить(отправить: false)
    }

    private func остановить(отправить: Bool) {
        ссылка?.invalidate()
        ссылка = nil
        прокрутка = nil
        NotificationCenter.default.removeObserver(self, name: UIApplication.willResignActiveNotification, object: nil)
        guard отправить, кадров >= Self.меньшеКадров else { return }
        let частота = кратчайший > 0 ? Int((1 / кратчайший).rounded()) : 0
        ЗамерыСкорости.листание(кадров: кадров, подвисаний: подвисаний, худший: худший, потеряно: потеряно,
                                длилось: длилось, частота: частота, где: где)
    }
}

extension View {
    /**
     Лента сообщает замеру подвисаний (ЗамерЛистания), что её начали листать. Ставится на содержимое ScrollView ленты:
     невидимый UIView находит над собой её UIScrollView и слушает только начало жеста прокрутки. где — «home» (витрина
     главной) или «feed» (лента раздела или поиска).
     */
    func замерПодвисанийЛистания(_ где: String) -> some View {
        background(
            ЯкорьЗамераЛистания(где: где)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        )
    }
}

private struct ЯкорьЗамераЛистания: UIViewRepresentable {
    let где: String

    func makeUIView(context: Context) -> ВидЗамераЛистания {
        let вид = ВидЗамераЛистания()
        вид.isUserInteractionEnabled = false
        вид.backgroundColor = .clear
        вид.где = где
        return вид
    }

    func updateUIView(_ uiView: ВидЗамераЛистания, context: Context) {
        if uiView.где != где { uiView.где = где }
    }

    static func dismantleUIView(_ uiView: ВидЗамераЛистания, coordinator: ()) {
        uiView.отцепиться()
    }
}

/// Невидимый вид в содержимом прокрутки ленты: цель у её panGestureRecognizer, пока он в окне.
final class ВидЗамераЛистания: UIView {
    var где = ""
    private weak var прокрутка: UIScrollView?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        отцепиться()
        guard window != nil else { return }
        /* Ближайшая прокрутка над видом — сама лента: якорь стоит на её содержимом, а не в горизонтальных рядах. */
        var узел = superview
        while let вид = узел {
            if let найдена = вид as? UIScrollView {
                найдена.panGestureRecognizer.addTarget(self, action: #selector(листают(_:)))
                прокрутка = найдена
                return
            }
            узел = вид.superview
        }
    }

    func отцепиться() {
        прокрутка?.panGestureRecognizer.removeTarget(self, action: #selector(листают(_:)))
        прокрутка = nil
    }

    @objc(klikoFeedScrollPan:)
    private func листают(_ жест: UIPanGestureRecognizer) {
        guard жест.state == .began, let прокрутка else { return }
        ЗамерЛистания.shared.начать(прокрутка, где: где)
    }
}
