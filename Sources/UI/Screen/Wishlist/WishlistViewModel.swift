import SwiftUI

@MainActor
final class WishlistViewModel: ObservableObject {
    @Published private(set) var items: [Item] = []
    @Published var searchText: String = ""

    nonisolated(unsafe) private let itemRepo = AppModule.shared.itemRepository

    func load() {
        Task {
            for await items in itemRepo.observeAll() {
                self.items = items.filter { $0.status == .wished }
            }
        }
    }

    func prioritizedItems() -> [Item] {
        let filtered = searchText.isEmpty
            ? items
            : items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }

        let order: [ItemPriority] = [.high, .medium, .low]
        return filtered.sorted { a, b in
            let pa = order.firstIndex(of: a.priority) ?? 3
            let pb = order.firstIndex(of: b.priority) ?? 3
            if pa != pb { return pa < pb }
            return a.updatedAt > b.updatedAt
        }
    }

    func delete(_ item: Item) async throws {
        ImageFileHelper.delete(paths: item.imageUrls.values)
        try await itemRepo.delete(item)
    }
}
