import SwiftUI

/// Экран входа по номеру + паролю. Ссылка на регистрацию — внизу.
struct LoginView: View {
    @EnvironmentObject private var app: AppState
    @State private var phone = ""
    @State private var password = ""
    @State private var error: String?
    @State private var busy = false
    @FocusState private var focus: Field?
    private enum Field { case phone, pass }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header

                VStack(spacing: 12) {
                    TextField("Номер телефона", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .focused($focus, equals: .phone)
                        .submitLabel(.next)
                        .onSubmit { focus = .pass }
                        .fieldStyle()

                    SecureField("Пароль", text: $password)
                        .textContentType(.password)
                        .focused($focus, equals: .pass)
                        .submitLabel(.go)
                        .onSubmit { Task { await submit() } }
                        .fieldStyle()

                    if let error {
                        Text(error).font(.footnote).foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button(action: { Task { await submit() } }) {
                        Group {
                            if busy { ProgressView().tint(.white) }
                            else { Text("Войти").fontWeight(.semibold) }
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                    }
                    .background(canSubmit ? Theme.green : Theme.green.opacity(0.4),
                                in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
                    .disabled(!canSubmit || busy)
                }

                NavigationLink { RegisterView() } label: {
                    HStack(spacing: 4) {
                        Text("Нет аккаунта?").foregroundStyle(Theme.muted)
                        Text("Зарегистрироваться").foregroundStyle(Theme.green2).bold()
                    }
                    .font(.subheadline)
                }
                .padding(.top, 4)

                Spacer(minLength: 24)
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Вход")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "bag.circle.fill")
                .font(.system(size: 56)).foregroundStyle(Theme.green)
            Text("Kliko.kz").font(.title).bold().foregroundStyle(Theme.ink)
            Text("Вход в аккаунт по номеру телефона")
                .font(.subheadline).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 16).padding(.bottom, 8)
    }

    private var canSubmit: Bool {
        phone.filter(\.isNumber).count >= 10 && !password.isEmpty
    }

    private func submit() async {
        guard canSubmit, !busy else { return }
        busy = true; error = nil; focus = nil
        error = await app.login(phone: phone, password: password)
        busy = false
    }
}

/// Единый стиль текстового поля формы авторизации.
private struct FieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14).padding(.vertical, 13)
            .background(Theme.mint, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.green.opacity(0.15)))
    }
}
extension View { func fieldStyle() -> some View { modifier(FieldStyle()) } }
