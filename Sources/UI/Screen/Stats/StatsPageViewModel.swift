import SwiftUI

@MainActor
final class StatsPageViewModel: ObservableObject {
    @Published private(set) var items: [Item] = []
    @Published private(set) var outfitLogs: [OutfitLog] = []
    @Published private(set) var coordinates: [Coordinate] = []
    @Published private(set) var brands: [Brand] = []
    @Published private(set) var spendingBySeason: [StyleSpending] = []
    @Published private(set) var totalSpending: Double = 0
    @Published private(set) var mostExpensive: ItemWithSpending? = nil
    @Published private(set) var spendingByBrand: [BrandSpending] = []
    @Published private(set) var spendingByCategory: [CategorySpending] = []
    @Published private(set) var spendingByStyle: [StyleSpending] = []
    @Published private(set) var monthlySpending: [MonthlySpending] = []
    @Published private(set) var wishlistBudget: Double = 0
    @Published private(set) var wishlistPriorityStats: [PriorityStats] = []

    private let coordinateRepo = AppModule.shared.coordinateRepository
    private let brandRepo = AppModule.shared.brandRepository
    private let itemRepo = AppModule.shared.itemRepository
    private let outfitRepo = AppModule.shared.outfitLogRepository
    private let priceRepo = AppModule.shared.priceRepository

    private var observationTasks: [Task<Void, Never>] = []

    func stopObserving() {
        observationTasks.forEach { $0.cancel() }
        observationTasks.removeAll()
    }

    func load() {
        guard observationTasks.isEmpty else { return }
        observationTasks.append(Task { [weak self, coordinateRepo] in
            for await value in coordinateRepo.observeAll() { guard !Task.isCancelled else { return }; self?.coordinates = value }
        })
        observationTasks.append(Task { [weak self, brandRepo] in
            for await value in brandRepo.observeAll() { guard !Task.isCancelled else { return }; self?.brands = value }
        })
        observationTasks.append(Task { [weak self, priceRepo] in
            for await value in priceRepo.getSpendingBySeason() { guard !Task.isCancelled else { return }; self?.spendingBySeason = value }
        })
        observationTasks.append(Task { [weak self, itemRepo] in
            for await items in itemRepo.observeAll() { guard !Task.isCancelled else { return }; self?.items = items }
        })
        observationTasks.append(Task { [weak self, outfitRepo] in
            for await logs in outfitRepo.observeAll() { guard !Task.isCancelled else { return }; self?.outfitLogs = logs }
        })
        observationTasks.append(Task { [weak self, priceRepo] in
            for await val in priceRepo.getTotalSpending() { guard !Task.isCancelled else { return }; self?.totalSpending = val }
        })
        observationTasks.append(Task { [weak self, priceRepo] in
            for await val in priceRepo.getMostExpensiveItem() { guard !Task.isCancelled else { return }; self?.mostExpensive = val }
        })
        observationTasks.append(Task { [weak self, priceRepo] in
            for await val in priceRepo.getSpendingByBrand() { guard !Task.isCancelled else { return }; self?.spendingByBrand = val }
        })
        observationTasks.append(Task { [weak self, priceRepo] in
            for await val in priceRepo.getSpendingByCategory() { guard !Task.isCancelled else { return }; self?.spendingByCategory = val }
        })
        observationTasks.append(Task { [weak self, priceRepo] in
            for await val in priceRepo.getSpendingByStyle() { guard !Task.isCancelled else { return }; self?.spendingByStyle = val }
        })
        observationTasks.append(Task { [weak self, priceRepo] in
            for await val in priceRepo.getMonthlySpending() { guard !Task.isCancelled else { return }; self?.monthlySpending = val }
        })
        observationTasks.append(Task { [weak self, priceRepo] in
            for await val in priceRepo.getWishlistTotalBudget() { guard !Task.isCancelled else { return }; self?.wishlistBudget = val }
        })
        observationTasks.append(Task { [weak self, priceRepo] in
            for await val in priceRepo.getWishlistByPriorityStats() { guard !Task.isCancelled else { return }; self?.wishlistPriorityStats = val }
        })
    }

    var totalItems: Int { items.count }
    var ownedCount: Int { items.filter { $0.status == .owned }.count }
    var wishedCount: Int { items.filter { $0.status == .wished }.count }
    var pendingCount: Int { items.filter { $0.status == .pendingBalance }.count }
    var totalCoordinates: Int { coordinates.count }
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

extension StatsPageViewModel {
    var topBrands: [(String, Int)] {
        let names = Dictionary(uniqueKeysWithValues: brands.map { ($0.id, $0.name) })
        return Dictionary(grouping: items.filter { $0.status != .wished }, by: \.brandId)
            .map { (names[$0.key] ?? "未知品牌", $0.value.count) }.sorted { $0.1 > $1.1 }
    }
    var quarterlySpending: [MonthlySpending] {
        var totals: [String: Double] = [:]
        for row in monthlySpending {
            let parts = row.yearMonth.split(separator: "-")
            guard parts.count == 2, let month = Int(parts[1]) else { continue }
            totals["\(parts[0])-Q\((month - 1) / 3 + 1)", default: 0] += row.totalSpending
        }
        return totals.sorted { $0.key < $1.key }.map { MonthlySpending(yearMonth: $0.key, totalSpending: $0.value) }
    }
}
