import SwiftUI

/// Прелоадер: показывается поверх WebView, пока грузится первая страница PWA.
/// Авто-тема (фон системный). Если добавишь в Assets.xcassets картинку «Logo» —
/// покажется она; пока её нет — брендовая плитка-заглушка с волной.
struct SplashView: View {
    @State private var pop = false
    @State private var wave = false

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 22) {
                logo
                    .scaleEffect(pop ? 1 : 0.82)
                    .opacity(pop ? 1 : 0)
                Text("kliko")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.green)
                    .opacity(pop ? 1 : 0)
                dots
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.62)) { pop = true }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { wave = true }
        }
    }

    @ViewBuilder private var logo: some View {
        if UIImage(named: "Logo") != nil {
            Image("Logo").resizable().scaledToFit()
                .frame(width: 104, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.green2, Theme.green],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 100, height: 100)
                    .shadow(color: Theme.green.opacity(0.35), radius: 18, y: 8)
                Image(systemName: "bag.fill")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(y: wave ? -3 : 3)
            }
        }
    }

    private var dots: some View {
        HStack(spacing: 7) {
            ForEach(0..<3) { i in
                Circle().fill(Theme.green2)
                    .frame(width: 8, height: 8)
                    .scaleEffect(wave ? 1 : 0.5)
                    .opacity(wave ? 1 : 0.4)
                    .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.18), value: wave)
            }
        }
        .padding(.top, 4)
    }
}

/// Экран «нет связи» — вместо белого WebView при обрыве сети (важно для App Store 4.2: ведёт себя как приложение, а не пустой браузер).
struct OfflineView: View {
    var retry: () -> Void
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 46, weight: .regular))
                    .foregroundStyle(Theme.muted)
                Text("Нет соединения")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text("Проверьте интернет и попробуйте снова.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                Button(action: retry) {
                    Text("Повторить")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 26).padding(.vertical, 12)
                        .background(Theme.green, in: Capsule())
                }
                .padding(.top, 4)
            }
            .padding(30)
        }
    }
}
