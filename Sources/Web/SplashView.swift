import SwiftUI
import Combine

// Бренд-цвета (зеркалят inc/brand.php: BRAND_GREEN/GREEN2/BEACON).
private let kGreen  = Color(red: 0x0f/255, green: 0x7a/255, blue: 0x44/255)   // #0f7a44
private let kGreen2 = Color(red: 0x16/255, green: 0xa3/255, blue: 0x4a/255)   // #16a34a
private let kBeacon = Color(red: 0x25/255, green: 0xd3/255, blue: 0x66/255)   // #25d366
/// Цвет вордмарка — как .klk-wm-svg на сайте: #0e1411 в светлой теме, #eef3f0 в тёмной.
private let kInk = Color(uiColor: UIColor { t in
    t.userInterfaceStyle == .dark ? UIColor(red: 0xee/255, green: 0xf3/255, blue: 0xf0/255, alpha: 1)
                                  : UIColor(red: 0x0e/255, green: 0x14/255, blue: 0x11/255, alpha: 1)
})

/// Прелоадер. Владелец 16.09.2026: «загрузка — логотип как в brand.php один в один, чтобы отличия не было; билд версию
/// пусть отражает; и загрузка не просто крутится, а прогресс-бар стильный, мощный».
///
/// ЛОГОТИП 1:1 С САЙТОМ. Значок — те же фигуры и те же анимации, что brand_logo_icon() и CSS klk-ring / klk-spin.
/// Надпись «Klıko.kz» — векторный PDF, отрисованный тем же шрифтом Unbounded 800, что на сайте (ресурсы WmKliko и WmKz:
/// разрезаны на две части, чтобы «Klıko» красилось цветом темы, а «.kz» оставалось зелёным). Точка над «ı» — мигающий
/// маяк, как klk-ring / klk-blink на сайте. Прежний вариант рисовал надпись системным округлым шрифтом и без маяка —
/// рядом с сайтом это читалось как другой логотип.
///
/// ПРОГРЕСС — настоящий: доля загрузки страницы из WKWebView.estimatedProgress (WebBridge.progress).
struct SplashView: View {
    @ObservedObject private var bridge = WebBridge.shared
    @State private var pop = false
    @State private var tipIdx = 0

    /* Только то, что правда работает: баллы выключены (про кэшбэк не пишем), проверка IMEI не подключена. */
    private let tips = [
        "Покупайте безопасно — через гаранта Kliko",
        "Оплата заморожена, пока вы не получите товар",
        "Торгуйтесь в чате — договорённая цена уходит в сделку",
        "Договаривайтесь в чате — переписка сохранится",
        "Верификация открывает безопасные сделки",
        "Ищите товары рядом — по геолокации"
    ]
    private let tipTimer = Timer.publish(every: 2.8, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                KlikoLogoIcon(size: 96)
                    .scaleEffect(pop ? 1 : 0.84)
                    .opacity(pop ? 1 : 0)
                KlikoWordmark(height: 40)
                    .padding(.top, 22)
                    .opacity(pop ? 1 : 0)
                Spacer()
                VStack(spacing: 16) {
                    LoadProgressBar(progress: bridge.progress)
                    bottomTips
                    Text(версияСборки)
                        .font(.caption2.weight(.medium).monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                .padding(.bottom, 34)
            }
            .padding(.horizontal, 32)
        }
        .onAppear { withAnimation(.spring(response: 0.55, dampingFraction: 0.62)) { pop = true } }
    }

    /// «Версия 1.5 · сборка 14» — на языке телефона. Номера из бандла (MARKETING_VERSION / CURRENT_PROJECT_VERSION).
    private var версияСборки: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "—"
        let b = info?["CFBundleVersion"] as? String ?? "—"
        switch String((Locale.preferredLanguages.first ?? "ru").prefix(2)) {
        case "kk": return "Нұсқа \(v) · жинақ \(b)"
        case "en": return "Version \(v) · build \(b)"
        case "ar": return "الإصدار \(v) · البناء \(b)"
        default:   return "Версия \(v) · сборка \(b)"
        }
    }

    private var bottomTips: some View {
        HStack(spacing: 7) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 12))
                .foregroundStyle(kGreen2)
            Text(tips[tipIdx])
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .id(tipIdx)
        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
        .frame(maxWidth: .infinity, minHeight: 38)
        .onReceive(tipTimer) { _ in
            withAnimation(.easeInOut(duration: 0.45)) { tipIdx = (tipIdx + 1) % tips.count }
        }
    }
}

// MARK: - Значок: brand_logo_icon() в системе координат 48×48, с анимациями сайта.
struct KlikoLogoIcon: View {
    let size: CGFloat

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, cs in
                let s = cs.width / 48
                func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
                let t = tl.date.timeIntervalSinceReferenceDate

                // Плашка с градиентом GREEN2 → GREEN, радиус 13/48.
                let badge = Path(roundedRect: CGRect(x: 0, y: 0, width: cs.width, height: cs.height),
                                 cornerRadius: 13 * s, style: .continuous)
                ctx.fill(badge, with: .linearGradient(Gradient(colors: [kGreen2, kGreen]),
                                                      startPoint: .zero,
                                                      endPoint: CGPoint(x: cs.width, y: cs.height)))

                // Пульс геолокации ПОД пином (как на сайте): кольцо r 8, белое .5, klk-ring 2.1 с — масштаб .4 → 1.55,
                // непрозрачность .85 → 0 к 70%.
                let ph = t.truncatingRemainder(dividingBy: 2.1) / 2.1
                let sc = 0.4 + 1.15 * kEaseOut(ph)
                let op = 0.85 * max(0, 1 - ph / 0.7)
                let rr = 8 * sc * s
                ctx.stroke(Path(ellipseIn: CGRect(x: 24 * s - rr, y: 19.5 * s - rr, width: 2 * rr, height: 2 * rr)),
                           with: .color(.white.opacity(0.5 * op)), lineWidth: 2 * sc * s)

                // Гео-пин — тот же путь, что M24 9.8c5.9 0 10.2 4.5 10.2 10.1C34.2 27 24 38 24 38S13.8 27 13.8 19.9…
                var pin = Path()
                pin.move(to: P(24, 9.8))
                pin.addCurve(to: P(34.2, 19.9), control1: P(29.9, 9.8), control2: P(34.2, 14.3))
                pin.addCurve(to: P(24, 38),     control1: P(34.2, 27),  control2: P(24, 38))
                pin.addCurve(to: P(13.8, 19.9), control1: P(24, 38),    control2: P(13.8, 27))
                pin.addCurve(to: P(24, 9.8),    control1: P(13.8, 14.3), control2: P(18.1, 9.8))
                pin.closeSubpath()
                ctx.fill(pin, with: .color(.white))

                // Циферблат r 6.2 в (24, 19.5).
                ctx.fill(Path(ellipseIn: CGRect(x: (24 - 6.2) * s, y: (19.5 - 6.2) * s, width: 12.4 * s, height: 12.4 * s)),
                         with: .color(kGreen))

                // Часовая стрелка → «10».
                var hh = Path(); hh.move(to: P(24, 19.5)); hh.addLine(to: P(21.4, 17.2))
                ctx.stroke(hh, with: .color(.white), style: StrokeStyle(lineWidth: 1.5 * s, lineCap: .round))

                // Минутная — полный оборот за 6 с (klk-spin).
                let ang = (t.truncatingRemainder(dividingBy: 6) / 6) * 2 * .pi
                var mh = Path(); mh.move(to: P(24, 19.5)); mh.addLine(to: P(27, 16.9))
                let rot = CGAffineTransform(translationX: 24 * s, y: 19.5 * s)
                    .rotated(by: ang).translatedBy(x: -24 * s, y: -19.5 * s)
                ctx.stroke(mh.applying(rot), with: .color(.white), style: StrokeStyle(lineWidth: 1.5 * s, lineCap: .round))

                // Центр стрелок r 1.05.
                ctx.fill(Path(ellipseIn: CGRect(x: (24 - 1.05) * s, y: (19.5 - 1.05) * s, width: 2.1 * s, height: 2.1 * s)),
                         with: .color(.white))
            }
            .frame(width: size, height: size)
            .shadow(color: kGreen.opacity(0.32), radius: 18, y: 9)
        }
    }
}

/// Плавный выход, близкий к cubic-bezier(.2,.6,.3,1) у klk-ring.
private func kEaseOut(_ x: Double) -> Double { 1 - pow(1 - max(0, min(1, x)), 3) }

// MARK: - Надпись «Klıko.kz»: brand_logo_wordmark() — viewBox 296×74, маяк над «ı» в (79, 15).
struct KlikoWordmark: View {
    let height: CGFloat

    var body: some View {
        let s = height / 74
        let w = 296 * s
        ZStack(alignment: .topLeading) {
            Image("WmKliko").resizable().renderingMode(.template).foregroundStyle(kInk)
                .frame(width: w, height: height)
            Image("WmKz").resizable().renderingMode(.original)
                .frame(width: w, height: height)
            // Маяк рисуем с запасом над надписью: кольцо растёт выше строки и не должно обрезаться.
            TimelineView(.animation) { tl in
                Canvas { ctx, _ in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    let c = CGPoint(x: 79 * s, y: (15 + 20) * s)
                    // Кольцо r 10, штрих 2.4 — klk-ring 2.1 с.
                    let ph = t.truncatingRemainder(dividingBy: 2.1) / 2.1
                    let sc = 0.4 + 1.15 * kEaseOut(ph)
                    let op = 0.85 * max(0, 1 - ph / 0.7)
                    let rr = 10 * sc * s
                    ctx.stroke(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: 2 * rr, height: 2 * rr)),
                               with: .color(kBeacon.opacity(op)), lineWidth: 2.4 * sc * s)
                    // Точка r 6.2 — klk-blink 1.5 с: 1 → .28 → 1.
                    let bp = t.truncatingRemainder(dividingBy: 1.5) / 1.5
                    let dop = 0.28 + 0.72 * (0.5 + 0.5 * cos(2 * Double.pi * bp))
                    let dr = 6.2 * s
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - dr, y: c.y - dr, width: 2 * dr, height: 2 * dr)),
                             with: .color(kBeacon.opacity(dop)))
                }
                .frame(width: w, height: height + 20 * s)
                .offset(y: -20 * s)
            }
        }
        .frame(width: w, height: height)
        .accessibilityElement()
        .accessibilityLabel("Kliko.kz")
    }
}

// MARK: - Прогресс загрузки: дорожка, заливка градиентом бренда со свечением и бегущим бликом, процент.
private struct LoadProgressBar: View {
    let progress: Double
    @State private var sheen = false

    var body: some View {
        let p = max(0.04, min(1, progress))
        VStack(spacing: 8) {
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient(colors: [kGreen, kGreen2, kBeacon], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(8, w * p))
                        .overlay(alignment: .leading) {
                            LinearGradient(colors: [.white.opacity(0), .white.opacity(0.6), .white.opacity(0)],
                                           startPoint: .leading, endPoint: .trailing)
                                .frame(width: 70)
                                .offset(x: sheen ? w : -70)
                        }
                        .clipShape(Capsule())
                        .shadow(color: kBeacon.opacity(0.55), radius: 8)
                        .animation(.spring(response: 0.45, dampingFraction: 0.9), value: p)
                }
            }
            .frame(height: 7)
            HStack {
                Text(подпись(p))
                Spacer()
                Text("\(Int((p * 100).rounded()))%").monospacedDigit()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .onAppear { withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { sheen = true } }
    }

    private func подпись(_ p: Double) -> String {
        let яз = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let готово = p >= 0.999
        switch яз {
        case "kk": return готово ? "Дайын" : "Жүктелуде"
        case "en": return готово ? "Ready" : "Loading"
        case "ar": return готово ? "جاهز" : "جارٍ التحميل"
        default:   return готово ? "Готово" : "Загружаем"
        }
    }
}

/// Экран «нет связи» — вместо белого WebView при обрыве сети (важно для App Store 4.2).
struct OfflineView: View {
    var retry: () -> Void
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 46, weight: .regular))
                    .foregroundStyle(.secondary)
                Text("Нет соединения")
                    .font(.title3.weight(.semibold))
                Text("Проверьте интернет и попробуйте снова.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(action: retry) {
                    Text("Повторить")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 26).padding(.vertical, 12)
                        .background(kGreen, in: Capsule())
                }
                .padding(.top, 4)
            }
            .padding(30)
        }
    }
}
