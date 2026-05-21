import SwiftUI

@MainActor
final class StatsPageViewModel: ObservableObject {
    @Published private(set) var items: [Item] = []
    @Published private(set) var outfitLogs: [OutfitLog] = []
    @Published private(set) var totalSpending: Double = 0
    @Published private(set) var mostExpensive: ItemWithSpending? = nil
    @Published private(set) var spendingByBrand: [BrandSpending] = []
    @Published private(set) var spendingByCategory: [CategorySpending] = []
    @Published private(set) var spendingByStyle: [StyleSpending] = []
    @Published private(set) var monthlySpending: [MonthlySpending] = []
    @Published private(set) var wishlistBudget: Double = 0
    @Published private(set) var wishlistPriorityStats: [PriorityStats] = []

    nonisolated(unsafe) private let itemRepo = AppModule.shared.itemRepository
    nonisolated(unsafe) private let outfitRepo = AppModule.shared.outfitLogRepository
    nonisolated(unsafe) private let priceRepo = AppModule.shared.priceRepository

    func load() {
        Task {
            for await items in itemRepo.observeAll() { self.items = items }
        }
        Task {
            for await logs in outfitRepo.observeAll() { self.outfitLogs = logs }
        }
        Task {
            for await val in priceRepo.getTotalSpending() { totalSpending = val }
        }
        Task {
            for await val in priceRepo.getMostExpensiveItem() { mostExpensive = val }
        }
        Task {
            for await val in priceRepo.getSpendingByBrand() { spendingByBrand = val }
        }
        Task {
            for await val in priceRepo.getSpendingByCategory() { spendingByCategory = val }
        }
        Task {
            for await val in priceRepo.getSpendingByStyle() { spendingByStyle = val }
        }
        Task {
            for await val in priceRepo.getMonthlySpending() { monthlySpending = val }
        }
        Task {
            for await val in priceRepo.getWishlistTotalBudget() { wishlistBudget = val }
        }
        Task {
            for await val in priceRepo.getWishlistByPriorityStats() { wishlistPriorityStats = val }
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
