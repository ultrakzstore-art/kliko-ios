import SwiftUI

/**
 ЗАГРУЗОЧНЫЙ ЭКРАН КАК НА САЙТЕ (владелец 26.09.2026: «лоадера почему нету?»).

 Копия #ulx-preloader главной сайта (разметка и стили — в home.html и css/marketplace.min.css):
  • фон на весь экран — #f4f7f5, в тёмной теме #0d0d14;
  • значок 90×90 (brand_logo_icon: плашка 48×48 с радиусом 13, градиент #16a34a → #0f7a44, белый пин, циферблат
    #0f7a44, стрелки; минутная крутится klk-spin 6 с, кольцо пульсирует klk-ring 2,1 с) с тенью
    drop-shadow(0 12px 26px rgba(15,122,68,.32));
  • надпись «Klıko.kz» 112×28 (viewBox 296×74, Unbounded 800 — те же векторные WmKliko и WmKz, что у KlikoWordmark),
    «.kz» зелёная #16a34a, маяк над «ı» — кольцо klk-ring и точка klk-blink 1,5 с;
  • между значком и надписью 14 (--m-3h), до колеса 20 (--m-5);
  • колесо .prg 34×34, обводка 3 (#d7e8df и зелёный верх; в тёмной #26332c и --mk-bright), оборот 0,8 с;
  • подсказка .phint внизу (bottom 34, поля 24, 14 пт, #5f6f66 / #93a49b, жирное — зелёным), новая каждые 2,6 с:
    гаснет за 0,35 с, меняется и загорается; первая — случайная, как у скрипта сайта;
  • появление ulxp-in 0,5 с cubic-bezier(.2,.8,.25,1): масштаб .86 → 1 и непрозрачность 0 → 1. Уход (0,45 с) —
    у того, кто показывает экран (RootWebView).

 «Уменьшение движения» — как @media(prefers-reduced-motion:reduce) сайта: стоят стрелка, кольца, колесо и появление.
 Точку маяка и смену подсказок сайт не останавливает — здесь тоже.
 */
struct SitePreloader: View {
    @Environment(\.accessibilityReduceMotion) private var тихо
    @State private var появилось = false
    @State private var номер = Int.random(in: 0..<ПодсказкиПрелоадера.список.count)
    @State private var подсказкаВидна = true
    @ScaledMetric(relativeTo: .subheadline) private var кегль: CGFloat = 14

    var body: some View {
        /* #ulx-preloader — position:fixed; inset:0: весь экран, под вырезом и домашней полосой тоже; значок с колесом —
           по центру экрана, подсказка — в 34 от его низа. */
        ZStack(alignment: .bottom) {
            ПодсказкиПрелоадера.фон

            VStack(spacing: 20) {
                VStack(spacing: 14) {
                    ЗначокПрелоадера(стоит: тихо)
                        .frame(width: 90, height: 90)
                        .shadow(color: Color(uiColor: Theme.hex(0x0F7A44, 0.32)), radius: 13, x: 0, y: 12)
                    НадписьПрелоадера(стоит: тихо)
                        .frame(width: 112, height: 28)
                }
                .scaleEffect(появилось ? 1 : 0.86)
                .opacity(появилось ? 1 : 0)

                SiteSpinner(размер: 34, толщина: 3,
                            дорожка: Theme.цвет(0xD7E8DF, 0x26332C),
                            верх: Theme.цвет(0x1D7D4A, 0x5CD39A),
                            период: 0.8, стоит: тихо)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            подсказка
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ПодсказкиПрелоадера.загрузка)
        .accessibilityAddTraits(.updatesFrequently)
        .onAppear {
            if тихо {
                появилось = true
            } else {
                withAnimation(.timingCurve(0.2, 0.8, 0.25, 1, duration: 0.5)) { появилось = true }
            }
        }
        .task { await менятьПодсказки() }
    }

    private var подсказка: some View {
        Text(ПодсказкиПрелоадера.строка(ПодсказкиПрелоадера.список[номер % ПодсказкиПрелоадера.список.count],
                                        кегль: кегль))
            .font(.system(size: кегль))
            .foregroundStyle(ПодсказкиПрелоадера.цветТекста)
            .multilineTextAlignment(.center)
            .lineSpacing(кегль * 0.3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 540)
            .padding(.horizontal, 24)
            .padding(.bottom, 34)
            .opacity(подсказкаВидна ? 1 : 0)
    }

    /// Скрипт сайта: setInterval 2600 — гаснет (transition .35s ease), через 350 мс новая и загорается.
    private func менятьПодсказки() async {
        let переход = Animation.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.35)
        try? await Task.sleep(nanoseconds: 2_600_000_000)
        while !Task.isCancelled {
            withAnimation(переход) { подсказкаВидна = false }
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { break }
            номер = (номер + 1) % ПодсказкиПрелоадера.список.count
            withAnimation(переход) { подсказкаВидна = true }
            try? await Task.sleep(nanoseconds: 2_250_000_000)
        }
    }
}

/// Сигнал «у нативной главной или ленты есть первые данные» — по нему уходит загрузочный экран запуска (RootWebView).
@MainActor
final class ЗаставкаЗапуска: ObservableObject {
    static let shared = ЗаставкаЗапуска()
    @Published private(set) var данныеЕсть = false

    private init() {}

    func данныеПришли() {
        if !данныеЕсть { данныеЕсть = true }
    }
}

// MARK: - Значок brand_logo_icon() — viewBox 48×48

private struct ЗначокПрелоадера: View {
    let стоит: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: стоит)) { шкала in
            let t = шкала.date.timeIntervalSinceReferenceDate
            Canvas { ctx, размер in
                let s = размер.width / 48
                func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
                let центр = P(24, 19.5)

                // <rect width=48 height=48 rx=13 fill=url(#klkg)>: градиент из левого верхнего угла в правый нижний.
                let плашка = Path(roundedRect: CGRect(origin: .zero, size: размер), cornerRadius: 13 * s)
                ctx.fill(плашка, with: .linearGradient(Gradient(colors: [ПодсказкиПрелоадера.зелёный2,
                                                                          ПодсказкиПрелоадера.зелёный]),
                                                       startPoint: .zero,
                                                       endPoint: CGPoint(x: размер.width, y: размер.height)))

                // <circle r=8 stroke=rgba(255,255,255,.5) stroke-width=2 class=klk-ring> — под пином.
                let пульс = ПодсказкиПрелоадера.пульс(t, стоит: стоит)
                let rr = 8 * пульс.масштаб * s
                ctx.stroke(Path(ellipseIn: CGRect(x: центр.x - rr, y: центр.y - rr, width: 2 * rr, height: 2 * rr)),
                           with: .color(Color.white.opacity(0.5 * пульс.прозрачность)),
                           lineWidth: 2 * пульс.масштаб * s)

                // Пин: M24 9.8c5.9 0 10.2 4.5 10.2 10.1C34.2 27 24 38 24 38S13.8 27 13.8 19.9C13.8 14.3 18.1 9.8 24 9.8z
                var пин = Path()
                пин.move(to: P(24, 9.8))
                пин.addCurve(to: P(34.2, 19.9), control1: P(29.9, 9.8), control2: P(34.2, 14.3))
                пин.addCurve(to: P(24, 38), control1: P(34.2, 27), control2: P(24, 38))
                пин.addCurve(to: P(13.8, 19.9), control1: P(24, 38), control2: P(13.8, 27))
                пин.addCurve(to: P(24, 9.8), control1: P(13.8, 14.3), control2: P(18.1, 9.8))
                пин.closeSubpath()
                ctx.fill(пин, with: .color(.white))

                // Циферблат r 6.2, #0f7a44.
                let rc = 6.2 * s
                ctx.fill(Path(ellipseIn: CGRect(x: центр.x - rc, y: центр.y - rc, width: 2 * rc, height: 2 * rc)),
                         with: .color(ПодсказкиПрелоадера.зелёный))

                // Стрелки: stroke #fff 1.5, round. Часовая — к (21.4, 17.2).
                let штрих = StrokeStyle(lineWidth: 1.5 * s, lineCap: .round)
                var часовая = Path()
                часовая.move(to: центр)
                часовая.addLine(to: P(21.4, 17.2))
                ctx.stroke(часовая, with: .color(.white), style: штрих)

                // Минутная .klk-hand — к (27, 16.9), оборот вокруг (24, 19.5) за 6 с, линейно.
                let доля = стоит ? 0 : t.truncatingRemainder(dividingBy: 6) / 6
                let поворот = CGAffineTransform(translationX: центр.x, y: центр.y)
                    .rotated(by: CGFloat(доля * 2 * Double.pi))
                    .translatedBy(x: -центр.x, y: -центр.y)
                var минутная = Path()
                минутная.move(to: центр)
                минутная.addLine(to: P(27, 16.9))
                ctx.stroke(минутная.applying(поворот), with: .color(.white), style: штрих)

                // Ось r 1.05.
                let ro = 1.05 * s
                ctx.fill(Path(ellipseIn: CGRect(x: центр.x - ro, y: центр.y - ro, width: 2 * ro, height: 2 * ro)),
                         with: .color(.white))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Надпись brand_logo_wordmark() — viewBox 296×74

private struct НадписьПрелоадера: View {
    let стоит: Bool

    var body: some View {
        GeometryReader { г in
            let s = г.size.height / 74
            ZStack(alignment: .topLeading) {
                Image("WmKliko")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(ПодсказкиПрелоадера.чернила)
                Image("WmKz")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(ПодсказкиПрелоадера.зелёный2)
                /* Маяк: <g transform=translate(79,15)> — кольцо r 10, штрих 2.4, #25d366 (klk-ring) и точка r 6.2 (klk-blink).
                   Точку «уменьшение движения» сайта не останавливает. SVG обрезает всё, что за viewBox, — .clipped(). */
                TimelineView(.animation) { шкала in
                    let t = шкала.date.timeIntervalSinceReferenceDate
                    Canvas { ctx, _ in
                        let c = CGPoint(x: 79 * s, y: 15 * s)
                        let пульс = ПодсказкиПрелоадера.пульс(t, стоит: стоит)
                        let rr = 10 * пульс.масштаб * s
                        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: 2 * rr, height: 2 * rr)),
                                   with: .color(ПодсказкиПрелоадера.маяк.opacity(пульс.прозрачность)),
                                   lineWidth: 2.4 * пульс.масштаб * s)
                        let dr = 6.2 * s
                        ctx.fill(Path(ellipseIn: CGRect(x: c.x - dr, y: c.y - dr, width: 2 * dr, height: 2 * dr)),
                                 with: .color(ПодсказкиПрелоадера.маяк.opacity(ПодсказкиПрелоадера.мигание(t))))
                    }
                }
            }
            .frame(width: г.size.width, height: г.size.height)
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

// MARK: - Краски, движение и тексты

enum ПодсказкиПрелоадера {
    static let зелёный = Color(uiColor: Theme.hex(0x0F7A44))
    static let зелёный2 = Color(uiColor: Theme.hex(0x16A34A))
    static let маяк = Color(uiColor: Theme.hex(0x25D366))
    /// .klk-wm-svg: #0e1411 и #eef3f0.
    static let чернила = Theme.цвет(0x0E1411, 0xEEF3F0)
    /// #ulx-preloader: #f4f7f5 и #0d0d14 (тот же цвет у экрана запуска — LaunchBackground).
    static let фон = Theme.цвет(0xF4F7F5, 0x0D0D14)
    /// .phint: #5f6f66 и #93a49b.
    static let цветТекста = Theme.цвет(0x5F6F66, 0x93A49B)
    /// .phint b: --mk-green2 и --mk-bright тёмной темы.
    static let цветЖирного = Theme.цвет(0x1D7D4A, 0x5CD39A)

    /// klk-ring 2,1 с cubic-bezier(.2,.6,.3,1): масштаб .4 → 1.95 за весь период, непрозрачность .85 → 0 к 70 %.
    /// Стоит — кольцо как в разметке, без анимации: масштаб 1, непрозрачность 1.
    static func пульс(_ t: Double, стоит: Bool) -> (масштаб: CGFloat, прозрачность: Double) {
        if стоит { return (1, 1) }
        let p = t.truncatingRemainder(dividingBy: 2.1) / 2.1
        let масштаб = 0.4 + 1.55 * кривая(0.2, 0.6, 0.3, 1, p)
        let прозрачность = p < 0.7 ? 0.85 * (1 - кривая(0.2, 0.6, 0.3, 1, p / 0.7)) : 0
        return (CGFloat(масштаб), прозрачность)
    }

    /// klk-blink 1,5 с ease-in-out: 1 → .28 к середине → 1.
    static func мигание(_ t: Double) -> Double {
        let p = t.truncatingRemainder(dividingBy: 1.5) / 1.5
        if p < 0.5 { return 1 - 0.72 * кривая(0.42, 0, 0.58, 1, p / 0.5) }
        return 0.28 + 0.72 * кривая(0.42, 0, 0.58, 1, (p - 0.5) / 0.5)
    }

    /// cubic-bezier(x1, y1, x2, y2) CSS: y по x (x ищем делением пополам).
    static func кривая(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ x: Double) -> Double {
        let цель = min(1, max(0, x))
        func bx(_ u: Double) -> Double {
            let v = 1 - u
            return 3 * v * v * u * x1 + 3 * v * u * u * x2 + u * u * u
        }
        func by(_ u: Double) -> Double {
            let v = 1 - u
            return 3 * v * v * u * y1 + 3 * v * u * u * y2 + u * u * u
        }
        var низ = 0.0
        var верх = 1.0
        for _ in 0..<24 {
            let середина = (низ + верх) / 2
            if bx(середина) < цель { низ = середина } else { верх = середина }
        }
        return by((низ + верх) / 2)
    }

    /// Строка с <b>…</b> сайта: жирное — 700 и зелёным.
    static func строка(_ исходная: String, кегль: CGFloat) -> AttributedString {
        var итог = AttributedString()
        var жирный = false
        var остаток = Substring(исходная)
        while !остаток.isEmpty {
            let тег = жирный ? "</b>" : "<b>"
            guard let r = остаток.range(of: тег) else {
                итог.append(кусок(String(остаток), жирный: жирный, кегль: кегль))
                break
            }
            итог.append(кусок(String(остаток[..<r.lowerBound]), жирный: жирный, кегль: кегль))
            остаток = остаток[r.upperBound...]
            жирный.toggle()
        }
        return итог
    }

    private static func кусок(_ текст: String, жирный: Bool, кегль: CGFloat) -> AttributedString {
        var a = AttributedString(текст)
        if жирный {
            a.font = Font.system(size: кегль, weight: .bold)
            a.foregroundColor = цветЖирного
        }
        return a
    }

    /// aria-label «Загрузка…».
    static var загрузка: String {
        switch DesignText.язык {
        case "kk": return "Жүктелуде…"
        case "en": return "Loading…"
        case "ar": return "جارٍ التحميل…"
        default: return "Загрузка…"
        }
    }

    /// Подсказки #ulxp-hint на языке приложения. Русские — дословно из скрипта главной сайта (переменная H).
    static var список: [String] {
        switch DesignText.язык {
        case "kk": return kk
        case "en": return en
        case "ar": return ar
        default: return ru
        }
    }

    private static let ru: [String] = [
        "Покупайте безопасно — <b>деньги у нас, пока не проверите товар</b>",
        "Продавайте за 30 секунд: сфоткайте — <b>Kliko AI заполнит объявление</b>",
        "Подпишитесь на поиск — <b>пришлём пуш</b>, когда появится нужное",
        "У проверенных продавцов — <b>синяя галочка</b>",
        "Заказывайте <b>доставку и курьера</b> прямо из чата",
        "Нажмите на <b>знаки доверия</b> в объявлении — что даёт гарантия и доставка",
        "Предлагайте свою цену — <b>торгуйтесь</b> прямо в объявлении",
        "Аренда, обмен и услуги — <b>всё в одном месте</b>",
        "Общайтесь в чате — <b>видно, когда продавец онлайн</b>",
        "Сохраняйте в избранное — <b>ничего не потеряете</b>"
    ]

    private static let kk: [String] = [
        "Қауіпсіз сатып алыңыз — <b>тауарды тексергенше ақша бізде</b>",
        "30 секундта сатыңыз: суретке түсіріңіз — <b>Kliko AI хабарландыруды толтырады</b>",
        "Іздеуге жазылыңыз — <b>керегі шыққанда пуш жібереміз</b>",
        "Тексерілген сатушыларда — <b>көк белгі</b>",
        "<b>Жеткізу мен курьерді</b> тікелей чаттан тапсырыс беріңіз",
        "Хабарландырудағы <b>сенім белгілерін</b> басыңыз — кепілдік пен жеткізу не береді",
        "Өз бағаңызды ұсыныңыз — <b>тікелей хабарландыруда саудаласыңыз</b>",
        "Жалға беру, айырбас және қызметтер — <b>бәрі бір жерде</b>",
        "Чатта сөйлесіңіз — <b>сатушы желіде екені көрінеді</b>",
        "Таңдаулыларға сақтаңыз — <b>ештеңе жоғалмайды</b>"
    ]

    private static let en: [String] = [
        "Buy safely — <b>we hold the money until you check the item</b>",
        "Sell in 30 seconds: take a photo — <b>Kliko AI fills in the listing</b>",
        "Subscribe to a search — <b>we’ll send a push</b> when what you need appears",
        "Verified sellers have a <b>blue checkmark</b>",
        "Order <b>delivery and a courier</b> right from the chat",
        "Tap the <b>trust badges</b> in a listing — see what the guarantee and delivery give you",
        "Offer your price — <b>bargain</b> right in the listing",
        "Rentals, swaps and services — <b>all in one place</b>",
        "Chat with sellers — <b>see when they’re online</b>",
        "Save to favorites — <b>never lose a thing</b>"
    ]

    private static let ar: [String] = [
        "اشترِ بأمان — <b>نحتفظ بالمال حتى تتحقق من السلعة</b>",
        "بِع في 30 ثانية: التقط صورة — <b>Kliko AI يملأ الإعلان</b>",
        "اشترك في البحث — <b>سنرسل إشعارًا</b> عند ظهور ما تحتاجه",
        "لدى البائعين الموثَّقين — <b>علامة زرقاء</b>",
        "اطلب <b>التوصيل والمندوب</b> مباشرة من الدردشة",
        "اضغط على <b>علامات الثقة</b> في الإعلان — لترى ما يقدمه الضمان والتوصيل",
        "اقترح سعرك — <b>فاوِض</b> مباشرة في الإعلان",
        "الإيجار والمقايضة والخدمات — <b>كل شيء في مكان واحد</b>",
        "تحدث في الدردشة — <b>ترى متى يكون البائع متصلًا</b>",
        "احفظ في المفضلة — <b>لن يضيع منك شيء</b>"
    ]
}
