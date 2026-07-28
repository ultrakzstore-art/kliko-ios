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

    // Подсказки в тоне сайта (безопасность/фишки). Крутятся снизу, как на витрине.
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

// MARK: - Логотип (бейдж + гео-пин с часами + пульс), рисуется в системе координат 48×48
private struct KlikoLogo: View {
    let size: CGFloat
    @State private var pulse = false
    @State private var spin  = false

    var body: some View {
        ZStack {
            // Бейдж с градиентом (радиус 13/48 как в SVG)
            RoundedRectangle(cornerRadius: 48 * 13/48, style: .continuous)
                .fill(LinearGradient(colors: [kGreen2, kGreen], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 48, height: 48)

            // Гео-пин (белый)
            PinShape().fill(.white).frame(width: 48, height: 48)

            // Циферблат (зелёный) — r 6.2 в (24,19.5)
            Circle().fill(kGreen).frame(width: 12.4, height: 12.4).position(x: 24, y: 19.5)

            // Стрелки
            HourHand().stroke(.white, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .frame(width: 48, height: 48)
            MinuteHand().stroke(.white, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .frame(width: 48, height: 48)
                .rotationEffect(.degrees(spin ? 360 : 0), anchor: UnitPoint(x: 24.0/48.0, y: 19.5/48.0))

            // Центр стрелок
            Circle().fill(.white).frame(width: 2.1, height: 2.1).position(x: 24, y: 19.5)

            // Пульс геолокации (сонар) поверх — как «маяк» бренда
            Circle().stroke(Color.white.opacity(0.55), lineWidth: 2)
                .frame(width: 16, height: 16)
                .scaleEffect(pulse ? 1.9 : 0.45)
                .opacity(pulse ? 0 : 0.85)
                .position(x: 24, y: 19.5)
        }
        .frame(width: 48, height: 48)
        .scaleEffect(size / 48)
        .frame(width: size, height: size)
        .shadow(color: kGreen.opacity(0.32), radius: 18, y: 9)
        .onAppear {
            withAnimation(.easeOut(duration: 2.1).repeatForever(autoreverses: false)) { pulse = true }
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) { spin = true }
        }
    }
}

// Гео-пин (абсолютные координаты SVG в пространстве 48×48)
private struct PinShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 48
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
        var path = Path()
        path.move(to: p(24, 9.8))
        path.addCurve(to: p(34.2, 19.9), control1: p(29.9, 9.8), control2: p(34.2, 14.3))
        path.addCurve(to: p(24, 38),     control1: p(34.2, 27), control2: p(24, 38))
        path.addCurve(to: p(13.8, 19.9), control1: p(24, 38),   control2: p(13.8, 27))
        path.addCurve(to: p(24, 9.8),    control1: p(13.8, 14.3), control2: p(18.1, 9.8))
        path.closeSubpath()
        return path
    }
}

private struct HourHand: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 48
        var p = Path(); p.move(to: CGPoint(x: 24*s, y: 19.5*s)); p.addLine(to: CGPoint(x: 21.4*s, y: 17.2*s)); return p
    }
}
private struct MinuteHand: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 48
        var p = Path(); p.move(to: CGPoint(x: 24*s, y: 19.5*s)); p.addLine(to: CGPoint(x: 27*s, y: 16.9*s)); return p
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
