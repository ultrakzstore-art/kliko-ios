import SwiftUI
import UIKit   // UIPasteboard

/// Профиль вошедшего пользователя. Пока: карточка аккаунта, статус верификации,
/// заглушки будущих разделов и выход. Расширится в следующих фазах (сделки/объявления).
struct ProfileView: View {
    @EnvironmentObject private var app: AppState
    @State private var confirmLogout = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Circle().fill(Theme.mint).frame(width: 60, height: 60)
                        .overlay(Text(initials).font(.title3).bold().foregroundStyle(Theme.green2))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.user?.name ?? "—").font(.headline).foregroundStyle(Theme.ink)
                        if let p = app.user?.phonePretty {
                            Text(p).font(.subheadline).foregroundStyle(Theme.muted)
                        }
                        HStack(spacing: 6) {
                            if app.user?.verified == true {
                                badge("Проверенный", "checkmark.seal.fill", .blue)
                            }
                            if app.user?.isPro == true {
                                badge("PRO", "star.fill", Theme.green2)
                            }
                        }
                        .padding(.top, 2)
                    }
                    Spacer()
                }
                .padding(.vertical, 6)
            }

            if app.user?.verified != true {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "shield.lefthalf.filled").foregroundStyle(Theme.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Пройдите верификацию").font(.subheadline).fontWeight(.medium)
                            Text("Безопасные сделки и больше доверия покупателей")
                                .font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                }
            }

            Section("Скоро в приложении") {
                rowSoon("Мои сделки", "shield.checkerboard")
                rowSoon("Мои объявления", "square.grid.2x2")
                rowSoon("Сообщения", "message")
            }

            Section {
                Button(role: .destructive) { confirmLogout = true } label: {
                    Label("Выйти", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .navigationTitle("Профиль")
        .confirmationDialog("Выйти из аккаунта?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Выйти", role: .destructive) { Task { await app.logout() } }
            Button("Отмена", role: .cancel) {}
        }
    }

    private var initials: String {
        let parts = (app.user?.name ?? "").split(separator: " ").prefix(2)
        let s = parts.compactMap { $0.first }.map(String.init).joined()
        return s.isEmpty ? "K" : s.uppercased()
    }

    private func badge(_ text: String, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.caption2)
            Text(text).font(.caption2).fontWeight(.semibold)
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
        .foregroundStyle(color)
    }

    private func rowSoon(_ title: String, _ icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon).foregroundStyle(Theme.ink)
            Spacer()
            Text("скоро").font(.caption).foregroundStyle(Theme.muted)
        }
    }
}

/// Лист с разовым паролем сразу после регистрации.
struct NewPasswordSheet: View {
    let secret: OneTimeSecret
    var onDone: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.fill").font(.system(size: 44)).foregroundStyle(Theme.green)
            Text("Аккаунт создан").font(.title2).bold().foregroundStyle(Theme.ink)
            Text("Это ваш пароль для входа. Сохраните его — восстановить будет нельзя.")
                .font(.subheadline).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)

            Text(secret.password)
                .font(.system(.title2, design: .monospaced)).bold()
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 18).padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(Theme.mint, in: RoundedRectangle(cornerRadius: 12))
                .textSelection(.enabled)

            Button {
                UIPasteboard.general.string = secret.password
                copied = true
            } label: {
                Label(copied ? "Скопировано" : "Скопировать пароль",
                      systemImage: copied ? "checkmark" : "doc.on.doc")
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
            }
            .background(Theme.mint, in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(Theme.green2)

            Button(action: onDone) {
                Text("Я сохранил пароль").fontWeight(.semibold)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
            }
            .background(Theme.green, in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.white)

            Spacer()
        }
        .padding(24)
        .interactiveDismissDisabled(true)   // не закрыть свайпом — пароль важно сохранить
    }
}
