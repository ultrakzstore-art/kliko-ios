import SwiftUI

/// Экран переписки: лента сообщений + композер. Открывается из карточки товара («Написать»)
/// и из инбокса. Оба пути дают peerId (+ опц. listingId) → dm.php open.
struct ChatThreadView: View {
    @StateObject private var vm: ChatViewModel

    init(peerId: String, peerName: String, listingId: String = "") {
        _vm = StateObject(wrappedValue: ChatViewModel(peerId: peerId, peerName: peerName, listingId: listingId))
    }

    var body: some View {
        VStack(spacing: 0) {
            if vm.loading {
                ProgressView("Загружаем…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = vm.errorText, vm.messages.isEmpty {
                ContentUnavailableView(err, systemImage: "exclamationmark.bubble")
            } else {
                messagesScroll
            }
            if vm.blocked {
                Text("Диалог недоступен").font(.footnote).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity).padding(8).background(Theme.mint)
            } else {
                composer
            }
        }
        .navigationTitle(vm.peerName.isEmpty ? "Диалог" : vm.peerName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.start(); await vm.pollLoop() }   // pollLoop завершится при отмене task (уход с экрана)
    }

    private var messagesScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if vm.messages.isEmpty {
                        Text("Напишите первым — задайте вопрос по объявлению")
                            .font(.footnote).foregroundStyle(Theme.muted)
                            .padding(.top, 40)
                    }
                    ForEach(vm.messages) { m in bubble(m).id(m.id) }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
            }
            .onChange(of: vm.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    private func bubble(_ m: DMMessage) -> some View {
        HStack {
            if m.mine { Spacer(minLength: 40) }
            Text(m.display)
                .font(.body)
                .foregroundStyle(m.mine ? .white : Theme.ink)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(m.mine ? Theme.green : Theme.mint,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            if !m.mine { Spacer(minLength: 40) }
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Сообщение…", text: $vm.draft, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Theme.mint, in: RoundedRectangle(cornerRadius: 20))
            Button { Task { await vm.send() } } label: {
                Image(systemName: vm.sending ? "hourglass" : "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSend ? Theme.green : Theme.muted)
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private var canSend: Bool {
        !vm.sending && !vm.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
