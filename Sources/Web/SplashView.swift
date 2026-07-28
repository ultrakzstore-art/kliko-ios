import SwiftUI
import Combine

// Бренд-цвета (зеркалят inc/brand.php: BRAND_GREEN/GREEN2/BEACON).
private let kGreen  = Color(red: 0x0f/255, green: 0x7a/255, blue: 0x44/255)   // #0f7a44
private let kGreen2 = Color(red: 0x16/255, green: 0xa3/255, blue: 0x4a/255)   // #16a34a
private let kBeacon = Color(red: 0x25/255, green: 0xd3/255, blue: 0x66/255)   // #25d366

/// Прелоадер: настоящий логотип Kliko (бейдж + гео-пин с часами + пульс геолокации) и
/// вордмарк «Klıko.kz», а снизу — крутящиеся подсказки (как на сайте). Авто-тема.
struct SplashView: View {
    @State private var pop = false
    @State private var tipIdx = 0

    private let tips = [
        "Покупайте безопасно — через гаранта Kliko",
        "Оплата заморожена, пока вы не получите товар",
        "Проверяйте IMEI и VIN прямо в объявлении",
        "Договаривайтесь в чате — переписка сохранится",
        "Верификация открывает безопасные сделки",
        "Кэшбэк баллами с каждой покупки",
        "Ищите товары рядом — по геолокации"
    ]
    private let tipTimer = Timer.publish(every: 2.8, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                KlikoLogo(size: 104)
                    .scaleEffect(pop ? 1 : 0.84)
                    .opacity(pop ? 1 : 0)
                wordmark
                    .padding(.top, 20)
                    .opacity(pop ? 1 : 0)
                Spacer()
                bottomTips
                    .padding(.bottom, 44)
            }
            .padding(.horizontal, 30)
        }
        .onAppear { withAnimation(.spring(response: 0.55, dampingFraction: 0.62)) { pop = true } }
    }

    // «Klıko.kz» — дотлесс-ı, .kz акцентным зелёным (Unbounded недоступен → rounded heavy).
    private var wordmark: some View {
        (Text("Kl\u{0131}ko").foregroundColor(.primary) + Text(".kz").foregroundColor(kGreen2))
            .font(.system(size: 30, weight: .heavy, design: .rounded))
            .kerning(-0.3)
    }

    private var bottomTips: some View {
        VStack(spacing: 16) {
            LoaderDots()
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
            .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .opacity))
            .frame(maxWidth: .infinity, minHeight: 38)
        }
        // Таймер на стабильном контейнере (не на .id-подвиде) → подписка не пересоздаётся.
        .onReceive(tipTimer) { _ in
            withAnimation(.easeInOut(duration: 0.45)) { tipIdx = (tipIdx + 1) % tips.count }
        }
    }
}

// MARK: - Логотип: Canvas (гарантированно рендерится) в системе координат 48×48.
// Бейдж-градиент + белый гео-пин + зелёный циферблат + идущая минутная стрелка + пульс-сонар.
private struct KlikoLogo: View {
    let size: CGFloat

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, cs in
                let s = cs.width / 48
                func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
                let t = tl.date.timeIntervalSinceReferenceDate

                // Бейдж с градиентом (радиус 13/48)
                let badge = Path(roundedRect: CGRect(x: 0, y: 0, width: cs.width, height: cs.height),
                                 cornerRadius: 13 * s, style: .continuous)
                ctx.fill(badge, with: .linearGradient(Gradient(colors: [kGreen2, kGreen]),
                                                      startPoint: .zero,
                                                      endPoint: CGPoint(x: cs.width, y: cs.height)))
                // Гео-пин (белый)
                var pin = Path()
                pin.move(to: P(24, 9.8))
                pin.addCurve(to: P(34.2, 19.9), control1: P(29.9, 9.8), control2: P(34.2, 14.3))
                pin.addCurve(to: P(24, 38),     control1: P(34.2, 27),  control2: P(24, 38))
                pin.addCurve(to: P(13.8, 19.9), control1: P(24, 38),    control2: P(13.8, 27))
                pin.addCurve(to: P(24, 9.8),    control1: P(13.8, 14.3), control2: P(18.1, 9.8))
                pin.closeSubpath()
                ctx.fill(pin, with: .color(.white))

                // Циферблат (зелёный), r 6.2 в (24,19.5)
                ctx.fill(Path(ellipseIn: CGRect(x: (24-6.2)*s, y: (19.5-6.2)*s, width: 12.4*s, height: 12.4*s)),
                         with: .color(kGreen))

                // Часовая стрелка → «10»
                var hh = Path(); hh.move(to: P(24, 19.5)); hh.addLine(to: P(21.4, 17.2))
                ctx.stroke(hh, with: .color(.white), style: StrokeStyle(lineWidth: 1.5*s, lineCap: .round))

                // Минутная стрелка (идёт: полный оборот за 6с)
                let ang = (t.truncatingRemainder(dividingBy: 6) / 6) * 2 * .pi
                var mh = Path(); mh.move(to: P(24, 19.5)); mh.addLine(to: P(27, 16.9))
                let rot = CGAffineTransform(translationX: 24*s, y: 19.5*s)
                    .rotated(by: ang).translatedBy(x: -24*s, y: -19.5*s)
                ctx.stroke(mh.applying(rot), with: .color(.white), style: StrokeStyle(lineWidth: 1.5*s, lineCap: .round))

                // Центр стрелок
                ctx.fill(Path(ellipseIn: CGRect(x: (24-1.05)*s, y: (19.5-1.05)*s, width: 2.1*s, height: 2.1*s)),
                         with: .color(.white))

                // Пульс геолокации (сонар): растёт и гаснет, период 2.1с
                let ph = t.truncatingRemainder(dividingBy: 2.1) / 2.1
                let rr = 8 * (0.4 + 1.55 * ph) * s
                let ring = Path(ellipseIn: CGRect(x: 24*s - rr, y: 19.5*s - rr, width: 2*rr, height: 2*rr))
                ctx.stroke(ring, with: .color(.white.opacity(0.85 * (1 - ph))), lineWidth: 2*s)
            }
            .frame(width: size, height: size)
            .shadow(color: kGreen.opacity(0.32), radius: 18, y: 9)
        }
    }
}

// Три пульсирующие точки-лоадер
private struct LoaderDots: View {
    @State private var on = false
    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<3) { i in
                Circle().fill(kGreen2)
                    .frame(width: 8, height: 8)
                    .scaleEffect(on ? 1 : 0.5)
                    .opacity(on ? 1 : 0.4)
                    .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.18), value: on)
            }
        }
        .onAppear { on = true }
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
