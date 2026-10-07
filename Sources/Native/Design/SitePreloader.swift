import SwiftUI

/**
 ПРИВЕТСТВЕННЫЙ ЭКРАН ЗАПУСКА (владелец 26.09.2026: «лоадера почему нету?»; 06.10.2026: «при запуске прогресс-бар
 красивый, приветственный лоадер сделай мощным, и пользы отмечай с анимацией»).

 Логотип — тот же, что у #ulx-preloader сайта (brand_logo_icon и brand_logo_wordmark, viewBox 48×48 и 296×74, те же
 klk-spin, klk-ring, klk-blink), фон — #f4f7f5 и #0d0d14, как у экрана запуска iOS (LaunchBackground): между ними нет
 вспышки, и строка состояния при сплэше остаётся системной (SceneDelegate). Зелень шапки приложения (шапкаВерх →
 зелёныйЯркий) — в мягком свечении за логотипом, в значках польз и в заливке прогресса.
  • Логотип появляется (масштаб .86 → 1) и потом «дышит» — едва заметно растёт и опадает, свечение за ним тоже.
  • Карусель польз: значок в зелёном кружке, заголовок и строка; новая каждые 1,2 с — въезжает сбоку с проявлением,
    точки внизу показывают, какая. Пользы — только то, что правда есть в приложении (ПользыЗапуска).
  • Прогресс — настоящий, насколько это знает приложение. Готово (первые данные главной или ленты — ЗаставкаЗапуска;
    в веб-обёртке — страница отрисована) — полоса быстро добегает до 100 %. До того — плавное заполнение по времени
    (к восьмой секунде, потолку заставки, около 92 %), а в веб-обёртке не ниже доли загрузки страницы
    (WKWebView.estimatedProgress). Своих задержек здесь нет: уходит экран тогда, когда решит RootWebView.

 «Уменьшение движения» — стоят стрелка, кольца, дыхание, блик полосы; пользы сменяются проявлением, без сдвига.
 */
struct SitePreloader: View {
    @Environment(\.accessibilityReduceMotion) private var тихо
    @ObservedObject private var заставка = ЗаставкаЗапуска.shared
    @ObservedObject private var мост = WebBridge.shared
    @State private var появилось = false
    @State private var дышит = false
    @State private var доля: Double = 0.06
    @State private var номер = 0
    /// Набор читается один раз: пауза гаранта (ПаузаГаранта) меняться посреди заставки не должна.
    @State private var пользы: [ПользаЗапуска] = ПользыЗапуска.список

    /// Приложению есть что показать: у нативной ленты — первые данные, у веб-обёртки — отрисованная страница.
    private var готово: Bool { Config.нативнаяЛента ? заставка.данныеЕсть : мост.isLoaded }

    var body: some View {
        ZStack {
            ПодсказкиПрелоадера.фон
                .ignoresSafeArea()

            /* Мягкое зелёное свечение за логотипом — зелень шапки приложения. */
            RadialGradient(colors: [Theme.зелёныйЯркий.opacity(0.22), Theme.зелёныйЯркий.opacity(0)],
                           center: .center, startRadius: 4, endRadius: 210)
                .frame(width: 420, height: 420)
                .scaleEffect(дышит ? 1.12 : 0.94)
                .opacity(появилось ? 1 : 0)
                .offset(y: -110)
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                Spacer(minLength: 24)
                логотип
                Spacer(minLength: 24)
                КарусельПольз(пользы: пользы, номер: номер, тихо: тихо)
                    .frame(maxWidth: 440)
                    .padding(.horizontal, 20)
                ПолосаЗапуска(доля: доля, готово: готово, тихо: тихо)
                    .frame(maxWidth: 400)
                    .padding(.horizontal, 40)
                    .padding(.top, 26)
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ПодсказкиПрелоадера.загрузка)
        .accessibilityValue(Text(verbatim: "\(Int((доля * 100).rounded()))%"))
        .accessibilityAddTraits(.updatesFrequently)
        .onAppear {
            if тихо {
                появилось = true
            } else {
                withAnimation(.timingCurve(0.2, 0.8, 0.25, 1, duration: 0.5)) { появилось = true }
                withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true).delay(0.5)) { дышит = true }
            }
            /* Данные уже есть (лента с диска, стартовые данные сборки) — полоса не прыгает, а плавно добегает за 0,5 с,
               пока длится минимум показа (0,6 с, RootWebView). */
            if готово {
                if тихо { доля = 1 } else { withAnimation(.easeInOut(duration: 0.5)) { доля = 1 } }
            }
        }
        .onChange(of: готово) { _, есть in
            guard есть else { return }
            if тихо { доля = 1 } else { withAnimation(.easeOut(duration: 0.3)) { доля = 1 } }
        }
        .task { await заполнять() }
        .task { await листать() }
    }

    private var логотип: some View {
        VStack(spacing: 16) {
            ЗначокПрелоадера(стоит: тихо)
                .frame(width: 96, height: 96)
                .shadow(color: Color(uiColor: Theme.hex(0x0F7A44, дышит ? 0.40 : 0.28)),
                        radius: дышит ? 18 : 13, x: 0, y: 12)
            НадписьПрелоадера(стоит: тихо)
                .frame(width: 128, height: 32)
        }
        .scaleEffect(появилось ? 1 : 0.86)
        .scaleEffect(дышит ? 1.035 : 1)
        .opacity(появилось ? 1 : 0)
    }

    /// Плавное заполнение до готовности: быстро в начале и всё медленнее к 92 % — никогда не «застревает» на месте.
    /// Готово — onChange добегает до 100 %.
    @MainActor
    private func заполнять() async {
        let старт = Date()
        while !Task.isCancelled {
            if готово { return }
            let t = Date().timeIntervalSince(старт)
            let поВремени = 0.06 + 0.86 * (1 - exp(-t / 2.4))
            let поСтранице = Config.нативнаяЛента ? 0 : мост.progress * 0.95
            let цель = min(0.95, max(доля, поВремени, поСтранице))
            if тихо {
                доля = цель
            } else {
                withAnimation(.linear(duration: 0.12)) { доля = цель }
            }
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
    }

    /// Новая польза каждые 1,2 с, по кругу.
    @MainActor
    private func листать() async {
        guard пользы.count > 1 else { return }
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if Task.isCancelled { break }
            let следующий = (номер + 1) % пользы.count
            if тихо {
                withAnimation(.easeInOut(duration: 0.25)) { номер = следующий }
            } else {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { номер = следующий }
            }
        }
    }
}

// MARK: - Карусель польз

private struct КарусельПольз: View {
    let пользы: [ПользаЗапуска]
    let номер: Int
    let тихо: Bool

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                if !пользы.isEmpty {
                    КартаПользы(польза: пользы[номер % пользы.count], тихо: тихо)
                        .id(номер)
                        .transition(переход)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 78)
            HStack(spacing: 6) {
                ForEach(пользы.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == номер % max(1, пользы.count) ? Theme.зелёныйЯркий : Theme.линия)
                        .frame(width: i == номер % max(1, пользы.count) ? 18 : 6, height: 6)
                }
            }
        }
    }

    private var переход: AnyTransition {
        if тихо { return .opacity }
        return .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                           removal: .move(edge: .leading).combined(with: .opacity))
    }
}

private struct КартаПользы: View {
    let польза: ПользаЗапуска
    let тихо: Bool
    @State private var значокВиден = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Theme.шапкаВерх, Theme.зелёныйЯркий],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: польза.значок)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 48, height: 48)
            .shadow(color: Theme.зелёныйЯркий.opacity(0.35), radius: 8, x: 0, y: 4)
            .scaleEffect(значокВиден ? 1 : 0.55)
            .rotationEffect(.degrees(значокВиден ? 0 : -18))
            VStack(alignment: .leading, spacing: 3) {
                Text(польза.заголовок)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.текст)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(польза.строка)
                    .font(.footnote)
                    .foregroundStyle(ПодсказкиПрелоадера.цветТекста)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.линия, lineWidth: 1))
        .shadow(color: Color(uiColor: Theme.hex(0x0F7A44, 0.10)), radius: 14, x: 0, y: 6)
        .onAppear {
            if тихо {
                значокВиден = true
            } else {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.55).delay(0.08)) { значокВиден = true }
            }
        }
    }
}

// MARK: - Полоса прогресса: скруглённая дорожка, заливка зеленью шапки со свечением и бегущим бликом, процент.

private struct ПолосаЗапуска: View {
    let доля: Double
    let готово: Bool
    let тихо: Bool

    var body: some View {
        let p = max(0.04, min(1, доля))
        VStack(spacing: 8) {
            GeometryReader { г in
                let w = г.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.цвет(0xDCE9E1, 0x26332C))
                    Capsule()
                        .fill(LinearGradient(colors: [Theme.шапкаВерх, Theme.зелёныйЯркий, ПодсказкиПрелоадера.маяк],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(8, w * p))
                        .overlay(alignment: .leading) { блик(ширина: w) }
                        .clipShape(Capsule())
                        .shadow(color: ПодсказкиПрелоадера.маяк.opacity(0.5), radius: 6)
                }
            }
            .frame(height: 8)
            HStack {
                Text(подпись)
                Spacer()
                Text(verbatim: "\(Int((p * 100).rounded()))%")
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(ПодсказкиПрелоадера.цветТекста)
        }
        .environment(\.layoutDirection, .leftToRight)   // полоса растёт слева направо и в арабском, как у сайта
    }

    /// Блик пробегает по заливке за 1,3 с; при «Уменьшении движения» его нет.
    @ViewBuilder
    private func блик(ширина w: CGFloat) -> some View {
        if !тихо {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { шкала in
                let фаза = шкала.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.3) / 1.3
                LinearGradient(colors: [.white.opacity(0), .white.opacity(0.55), .white.opacity(0)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: 64)
                    .offset(x: -64 + CGFloat(фаза) * (w + 64))
            }
        }
    }

    private var подпись: String {
        switch DesignText.язык {
        case "kk": return готово ? "Дайын" : "Жүктелуде"
        case "en": return готово ? "Ready" : "Loading"
        case "ar": return готово ? "جاهز" : "جارٍ التحميل"
        default: return готово ? "Готово" : "Загружаем"
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

    /// aria-label «Загрузка…».
    static var загрузка: String {
        switch DesignText.язык {
        case "kk": return "Жүктелуде…"
        case "en": return "Loading…"
        case "ar": return "جارٍ التحميل…"
        default: return "Загрузка…"
        }
    }
}

// MARK: - Пользы платформы для экрана запуска

/// Одна польза: значок SF Symbols в зелёном кружке, заголовок и строка.
struct ПользаЗапуска: Identifiable {
    let id: String
    let значок: String
    let заголовок: String
    let строка: String
}

/**
 Пользы на экране запуска — ТОЛЬКО то, что приложение и сайт правда делают (сверено по коду 06.10.2026):
  • «Безопасная сделка» — гарант (SiteSafeDeal, DealMoney*). Обещаем лишь когда гарант работает по последней сверке
    (ПаузаГаранта.работаетПоСверке; до первой сверки — не обещаем): «деньги у Kliko, пока не получите товар» на паузе
    было бы неправдой.
  • «Знайте, с кем имеете дело» — верификация eGov (EgovWindow), синяя галочка, отзывы и рейтинг продавца.
  • «Kliko AI» — распознавание фото в подаче (Posting: «Сфотографируйте — Kliko AI заполнит всё сам»).
  • «Бесплатная доставка» — у объявления «Доставка бесплатно», когда её оплачивает продавец (SiteListingDelivery).
  • «Доставка по Казахстану» — СДЭК в другой город и курьер Яндекс Go по городу (SiteListingLocation, Eds).
  • «QR-код объявления» — окно ЛистQRОбъявления (ListingQR.swift).
 */
enum ПользыЗапуска {
    static var список: [ПользаЗапуска] {
        let язык = DesignText.язык
        let т = тексты[язык] ?? тексты["ru"]!
        var ключи: [(String, String)] = []
        if ПаузаГаранта.работаетПоСверке { ключи.append(("escrow", "lock.shield.fill")) }
        ключи.append(("verified", "checkmark.seal.fill"))
        ключи.append(("ai", "sparkles"))
        ключи.append(("freeship", "shippingbox.fill"))
        ключи.append(("delivery", "truck.box.fill"))
        ключи.append(("qr", "qrcode"))
        return ключи.map { ключ, значок in
            ПользаЗапуска(id: ключ, значок: значок,
                          заголовок: т[ключ + "_t"] ?? тексты["ru"]![ключ + "_t"] ?? "",
                          строка: т[ключ + "_s"] ?? тексты["ru"]![ключ + "_s"] ?? "")
        }
    }

    private static let тексты: [String: [String: String]] = [
        "ru": ["escrow_t": "Безопасная сделка", "escrow_s": "Деньги у Kliko, пока вы не получите товар",
               "verified_t": "Знайте, с кем имеете дело", "verified_s": "Проверка через eGov, отзывы и рейтинг продавца",
               "ai_t": "Kliko AI", "ai_s": "Сфотографируйте вещь — объявление заполнится само",
               "freeship_t": "Бесплатная доставка", "freeship_s": "Многие продавцы везут за свой счёт",
               "delivery_t": "Доставка по Казахстану", "delivery_s": "СДЭК в другой город, курьер Яндекс Go — по городу",
               "qr_t": "QR-код объявления", "qr_s": "Покажите или распечатайте — откроется в Kliko"],
        "kk": ["escrow_t": "Қауіпсіз мәміле", "escrow_s": "Тауарды алғанша ақша Kliko-да тұрады",
               "verified_t": "Кіммен іс істейтініңізді біліңіз", "verified_s": "eGov арқылы тексеру, сатушының пікірлері мен рейтингі",
               "ai_t": "Kliko AI", "ai_s": "Затты суретке түсіріңіз — хабарландыру өзі толтырылады",
               "freeship_t": "Тегін жеткізу", "freeship_s": "Көп сатушы өз есебінен жеткізеді",
               "delivery_t": "Қазақстан бойынша жеткізу", "delivery_s": "Басқа қалаға СДЭК, қала ішінде Яндекс Go курьері",
               "qr_t": "Хабарландырудың QR-коды", "qr_s": "Көрсетіңіз не басып шығарыңыз — Kliko-да ашылады"],
        "en": ["escrow_t": "Safe deal", "escrow_s": "Kliko holds the money until you get the item",
               "verified_t": "Know who you deal with", "verified_s": "eGov verification, seller reviews and rating",
               "ai_t": "Kliko AI", "ai_s": "Snap a photo — the listing fills itself in",
               "freeship_t": "Free delivery", "freeship_s": "Many sellers ship at their own cost",
               "delivery_t": "Delivery across Kazakhstan", "delivery_s": "CDEK to other cities, Yandex Go courier in town",
               "qr_t": "Listing QR code", "qr_s": "Show it or print it — opens right in Kliko"],
        "ar": ["escrow_t": "صفقة آمنة", "escrow_s": "يحتفظ Kliko بالمال حتى تستلم السلعة",
               "verified_t": "اعرف مع من تتعامل", "verified_s": "توثيق عبر eGov، ومراجعات البائع وتقييمه",
               "ai_t": "Kliko AI", "ai_s": "التقط صورة — يُملأ الإعلان تلقائيًا",
               "freeship_t": "توصيل مجاني", "freeship_s": "كثير من البائعين يوصلون على نفقتهم",
               "delivery_t": "توصيل في أنحاء كازاخستان", "delivery_s": "CDEK إلى المدن الأخرى، ومندوب Yandex Go داخل المدينة",
               "qr_t": "رمز QR للإعلان", "qr_s": "اعرضه أو اطبعه — يُفتح في Kliko"]
    ]
}
