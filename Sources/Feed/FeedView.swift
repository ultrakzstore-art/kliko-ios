import SwiftUI

struct FeedView: View {
    @StateObject private var vm = FeedViewModel()
    private let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            Group {
                if vm.items.isEmpty, vm.isLoading {
                    ProgressView("Загружаем…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = vm.errorText, vm.items.isEmpty {
                    ContentUnavailableView(err, systemImage: "wifi.exclamationmark")
                } else if vm.items.isEmpty {
                    ContentUnavailableView("Ничего не найдено", systemImage: "magnifyingglass")
                } else {
                    ScrollView {
                        LazyVGrid(columns: cols, spacing: 12) {
                            ForEach(vm.items) { item in
                                NavigationLink(value: item) { ItemCard(item: item) }
                                    .buttonStyle(.plain)
                                    .task { await vm.loadMoreIfNeeded(current: item) }
                            }
                        }
                        .padding(12)
                        if vm.isLoading { ProgressView().padding(.bottom, 16) }
                    }
                }
            }
            .navigationDestination(for: MarketItem.self) { ItemDetailView(item: $0) }
            .navigationTitle("Kliko.kz")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $vm.query, prompt: "Toyota Camry, iPhone…")
            .onSubmit(of: .search) { Task { await vm.search(vm.query) } }
            .refreshable { await vm.refresh() }
        }
        .task { if vm.items.isEmpty { await vm.refresh() } }
    }
}
