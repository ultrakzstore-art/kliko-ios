import SwiftUI

/// Упрощённая регистрация: имя + номер → сервер создаёт аккаунт и выдаёт разовый пароль
/// (его показывает RootView через app.pendingPassword). После успеха гейт сам откроет профиль.
struct RegisterView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var phone = ""
    @State private var error: String?
    @State private var busy = false
    @FocusState private var focus: Field?
    private enum Field { case name, phone }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 52)).foregroundStyle(Theme.green)
                    Text("Регистрация").font(.title2).bold().foregroundStyle(Theme.ink)
                    Text("Пароль придёт автоматически — сохраните его")
                        .font(.subheadline).foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 12)

                VStack(spacing: 12) {
                    TextField("Ваше имя", text: $name)
                        .textContentType(.name)
                        .focused($focus, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focus = .phone }
                        .fieldStyle()

                    TextField("Номер телефона", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .focused($focus, equals: .phone)
                        .fieldStyle()

                    if let error {
                        Text(error).font(.footnote).foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button(action: { Task { await submit() } }) {
                        Group {
                            if busy { ProgressView().tint(.white) }
                            else { Text("Создать аккаунт").fontWeight(.semibold) }
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                    }
                    .background(canSubmit ? Theme.green : Theme.green.opacity(0.4),
                                in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
                    .disabled(!canSubmit || busy)
                }

                Text("Регистрируясь, вы принимаете условия сервиса Kliko.kz")
                    .font(.caption2).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)

                Spacer(minLength: 24)
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Регистрация")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var canSubmit: Bool { phone.filter(\.isNumber).count >= 10 }

    private func submit() async {
        guard canSubmit, !busy else { return }
        busy = true; error = nil; focus = nil
        error = await app.register(phone: phone, name: name.trimmingCharacters(in: .whitespaces))
        busy = false
        // при успехе app.user выставлен → гейт покажет профиль, этот экран уедет сам
    }
}
