import SwiftUI
import UIKit

/**
 РАМКА КАРТОЧКИ ВИТРИНЫ СЛОЯМИ CORE ANIMATION (сборка 87, владелец 17.10.2026: «при скроллинге будто тяжело смартфону,
 нет ощущения лёгкости — как будто тяжёлое приложение»).

 Замер листания в CI (FeedScrollBench.swift, отладочная сборка, 16 с листания, ~960 кадров): карточка как есть — 261
 кадр, без рамки — 482, без вида фото — 383, без цены, фактов или подвала — 266–288. Подложку с тенью (ShapeStyle.shadow),
 обводку и золотое кольцо рисовал SwiftUI — растром на главном потоке для каждой новой ячейки списка. Теперь их рисует
 Core Animation, как в UIKit-приложениях: подложка — слой своего цвета со скруглением и тенью по готовому контуру
 (shadowPath — без расчёта по прозрачности и без растра), обводка и кольцо — слой поверх содержимого. Вид прежний: те же
 цвета (Theme.поверхность, Theme.линия, золото #e4c579 и кольцо #d9b24c), радиус Theme.Радиус.lg с плавным углом, тень
 0 / 4 / 5 тех же цветов, обводка 1 внутрь, у ТОПа и VIP кольцо 1,5 снаружи.

 Слои не ловят касаний и не видны VoiceOver. Цвета — по схеме из SwiftUI (тёмная), а не по признакам UIKit: тему
 приложения выбирает корень (KlikoHostingController), и представление получает ту же.
 */
struct ПодложкаКарточкиСлоем: UIViewRepresentable {
    let золотая: Bool
    let тёмная: Bool

    func makeUIView(context: Context) -> ВидПодложкиКарточки {
        ВидПодложкиКарточки()
    }

    func updateUIView(_ вид: ВидПодложкиКарточки, context: Context) {
        вид.настроить(золотая: золотая, тёмная: тёмная)
    }
}

/// Обводка карточки (и золотое кольцо ТОПа и VIP) — слой поверх содержимого.
struct ОбводкаКарточкиСлоем: UIViewRepresentable {
    let золотая: Bool
    let тёмная: Bool

    func makeUIView(context: Context) -> ВидОбводкиКарточки {
        ВидОбводкиКарточки()
    }

    func updateUIView(_ вид: ВидОбводкиКарточки, context: Context) {
        вид.настроить(золотая: золотая, тёмная: тёмная)
    }
}

/// Цвета рамки — те же, что у прежней рамки SwiftUI (ListingCard.рамкаКарточки, цветТени).
enum ЦветаРамкиКарточки {
    static let радиус: CGFloat = Theme.Радиус.lg

    static func подложка(тёмная: Bool) -> UIColor {
        тёмная ? Theme.hex(0x16161F) : Theme.hex(0xFFFFFF)
    }

    static func обводка(золотая: Bool, тёмная: Bool) -> UIColor {
        if золотая { return Theme.hex(0xE4C579) }
        return тёмная ? Theme.hex(0xFFFFFF, 0.10) : Theme.hex(0xE3ECE7)
    }

    static let кольцо: UIColor = Theme.hex(0xD9B24C)

    static func тень(золотая: Bool, тёмная: Bool) -> UIColor {
        if золотая { return UIColor(red: 176 / 255, green: 132 / 255, blue: 24 / 255, alpha: 0.28) }
        if тёмная { return UIColor(white: 0, alpha: 0.4) }
        return UIColor(red: 15 / 255, green: 81 / 255, blue: 50 / 255, alpha: 0.16)
    }
}

final class ВидПодложкиКарточки: UIView {
    private var золотая = false
    private var тёмная = false
    private var настроен = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        layer.cornerRadius = ЦветаРамкиКарточки.радиус
        layer.cornerCurve = .continuous
        layer.shadowOffset = CGSize(width: 0, height: 4)
        layer.shadowRadius = 5
        layer.shadowOpacity = 1
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func настроить(золотая: Bool, тёмная: Bool) {
        guard !настроен || золотая != self.золотая || тёмная != self.тёмная else { return }
        настроен = true
        self.золотая = золотая
        self.тёмная = тёмная
        layer.backgroundColor = ЦветаРамкиКарточки.подложка(тёмная: тёмная).cgColor
        layer.shadowColor = ЦветаРамкиКарточки.тень(золотая: золотая, тёмная: тёмная).cgColor
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let контур = UIBezierPath(roundedRect: bounds, cornerRadius: ЦветаРамкиКарточки.радиус).cgPath
        if layer.shadowPath != контур { layer.shadowPath = контур }
    }
}

final class ВидОбводкиКарточки: UIView {
    private let кольцо = CALayer()
    private var золотая = false
    private var тёмная = false
    private var настроен = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        backgroundColor = .clear
        layer.cornerRadius = ЦветаРамкиКарточки.радиус
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        /* .top-card сайта: снаружи кольцо 1,5 (box-shadow 0 0 0 1.5px) — слой на 1,5 больше карточки, обводка внутрь. */
        кольцо.cornerRadius = ЦветаРамкиКарточки.радиус + 1.5
        кольцо.cornerCurve = .continuous
        кольцо.borderWidth = 1.5
        кольцо.borderColor = ЦветаРамкиКарточки.кольцо.cgColor
        кольцо.isHidden = true
        layer.addSublayer(кольцо)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func настроить(золотая: Bool, тёмная: Bool) {
        guard !настроен || золотая != self.золотая || тёмная != self.тёмная else { return }
        настроен = true
        self.золотая = золотая
        self.тёмная = тёмная
        layer.borderColor = ЦветаРамкиКарточки.обводка(золотая: золотая, тёмная: тёмная).cgColor
        кольцо.isHidden = !золотая
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        кольцо.frame = bounds.insetBy(dx: -1.5, dy: -1.5)
        CATransaction.commit()
    }
}
