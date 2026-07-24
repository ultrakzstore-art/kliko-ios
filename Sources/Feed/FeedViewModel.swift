import Foundation

@MainActor
final class FeedViewModel: ObservableObject {
    @Published var items: [MarketItem] = []
    @Published var isLoading = false
    @Published var errorText: String?
    @Published var query = ""

    private var page = 1
    private var canLoadMore = true

    func refresh() async {
        page = 1; canLoadMore = true
        await load(reset: true)
    }

    func loadMoreIfNeeded(current item: MarketItem) async {
        guard canLoadMore, !isLoading, let last = items.last, last.id == item.id else { return }
        page += 1
        await load(reset: false)
    }

    func search(_ text: String) async {
        query = text.trimmingCharacters(in: .whitespaces)
        page = 1; canLoadMore = true
        await load(reset: true)
    }

    private func load(reset: Bool) async {
        isLoading = true; errorText = nil
        defer { isLoading = false }
        do {
            let batch = try await API.shared.feed(page: page, q: query)
            if reset { items = batch } else { items.append(contentsOf: batch) }
            if batch.isEmpty { canLoadMore = false }
        } catch {
            errorText = "Не удалось загрузить ленту. Проверьте интернет."
        }
    }
}
