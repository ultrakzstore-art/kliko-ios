import SwiftUI

@main
struct KlikoApp: App {
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .tint(Theme.green)
                .task { await app.bootstrap() }
                // Разовый пароль после регистрации — на самом верхнем уровне,
                // чтобы не пропал при переключении гейта на профиль.
                .sheet(item: $app.pendingPassword) { secret in
                    NewPasswordSheet(secret: secret) { app.pendingPassword = nil }
                }
        }
    }
}

/// Две вкладки: барахолка (без входа) и профиль (вход при необходимости).
struct RootView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        TabView {
            FeedView()
                .tabItem { Label("Барахолка", systemImage: "square.grid.2x2.fill") }

            InboxView()
                .tabItem { Label("Чаты", systemImage: "bubble.left.and.bubble.right.fill") }

            ProfileTab()
                .tabItem { Label("Профиль", systemImage: "person.crop.circle.fill") }
        }
    }
}

/// Вкладка профиля: если вошли — профиль, иначе — экран входа (внутри своего NavigationStack).
struct ProfileTab: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        NavigationStack {
            if app.isAuthed {
                ProfileView()
            } else {
                LoginView()
            }
        }
    }
}
