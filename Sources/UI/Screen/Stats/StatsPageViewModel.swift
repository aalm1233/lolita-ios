import SwiftUI

@MainActor
final class StatsPageViewModel: ObservableObject {
    @Published private(set) var items: [Item] = []
    @Published private(set) var outfitLogs: [OutfitLog] = []

    private let itemRepo = AppModule.shared.itemRepository
    private let outfitRepo = AppModule.shared.outfitLogRepository

    func load() {
        Task {
            for await items in itemRepo.observeAll() { self.items = items }
        }
        Task {
            for await logs in outfitRepo.observeAll() { self.outfitLogs = logs }
        }
    }

    var totalItems: Int { items.count }
    var ownedCount: Int { items.filter { $0.status == .owned }.count }
    var wishedCount: Int { items.filter { $0.status == .wished }.count }
    var totalOutfits: Int { outfitLogs.count }

    var styleDistribution: [(String, Int)] {
        Dictionary(grouping: items) { $0.style ?? "未分类" }
            .map { ($0.key, $0.value.count) }
            .sorted { $0.1 > $1.1 }
    }

    var categoryDistribution: [(String, Int)] {
        items.reduce(into: [:]) { dict, item in
            let key = "\(item.categoryId)"
            dict[key, default: 0] += 1
        }.map { ($0.key, $0.value) }
        .sorted { $0.1 > $1.1 }
    }
}
