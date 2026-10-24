import SwiftUI
@preconcurrency import GRDB

enum StatsItemFilter: Hashable {
    case status(ItemStatus)
    case attribute(String, String, ownedOnly: Bool)
    case attributes(String, [String], ownedOnly: Bool)
    case paymentPeriod(String)
    case priority(ItemPriority)

    var title: String {
        switch self {
        case .status(.owned): return "已拥有服饰"
        case .status(.pendingPayment): return "待付款服饰"
        case .status(.pendingReview): return "待核对服饰"
        case .status(.pendingBalance): return "待尾款服饰"
        case .status(.wished): return "愿望单"
        case .attribute(let dimension, let value, _): return "\(value) · \(dimension)"
        case .attributes(let dimension, _, _): return "其他 · \(dimension)"
        case .paymentPeriod(let period): return "\(period) 已付服饰"
        case .priority(let priority): return "\(priority == .high ? "高" : priority == .low ? "低" : "中")优先心愿"
        }
    }

    func apply(to items: [Item], brands: [Brand], categories: [Category], prices: [Price], payments: [Payment]) -> [Item] {
        let brandNames = Dictionary(uniqueKeysWithValues: brands.map { ($0.id, $0.name) })
        let categoryNames = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
        let priceItems = Dictionary(uniqueKeysWithValues: prices.map { ($0.id, $0.itemId) })
        func matches(_ item: Item, dimension: String, value: String) -> Bool {
            switch dimension {
            case "品牌": return brandNames[item.brandId] == value
            case "分类": return categoryNames[item.categoryId] == value
            case "季节": return ItemCollectionFilter.seasons(in: item.season).contains(value)
            default: return (item.style?.isEmpty == false ? item.style! : "未分类") == value
            }
        }
        var paidItems: Set<Int64> = []
        if case .paymentPeriod(let period) = self {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .current
            for payment in payments where payment.isPaid {
                guard let paidDate = payment.paidDate else { continue }
                let date = Date(timeIntervalSince1970: Double(paidDate) / 1000)
                let year = calendar.component(.year, from: date)
                let month = calendar.component(.month, from: date)
                let key = period.contains("Q") ? "\(year)-Q\((month - 1) / 3 + 1)" : String(format: "%04d-%02d", year, month)
                if key == period, let itemId = priceItems[payment.priceId] { paidItems.insert(itemId) }
            }
        }
        return items.filter { item in
            switch self {
            case .status(let status): return item.status == status
            case .priority(let priority): return item.status == .wished && item.priority == priority
            case .paymentPeriod: return paidItems.contains(item.id)
            case .attribute(let dimension, let value, let ownedOnly):
                guard !ownedOnly || item.status == .owned else { return false }
                return matches(item, dimension: dimension, value: value)
            case .attributes(let dimension, let values, let ownedOnly):
                guard !ownedOnly || item.status == .owned else { return false }
                return values.contains { matches(item, dimension: dimension, value: $0) }
            }
        }.sorted { $0.updatedAt == $1.updatedAt ? $0.id > $1.id : $0.updatedAt > $1.updatedAt }
    }
}

enum StatsDistributionChartStyle: String, CaseIterable {
    case donut = "环图", pie = "饼图", bar = "柱状"
}

enum StatsTrendChartStyle: String, CaseIterable {
    case line = "折线", bar = "柱状"
}

struct StatsChartValue: Identifiable, Sendable, Equatable {
    let name: String
    let amount: Double
    var members: [String] = []
    var id: String { name }
}

enum StatsChartSelection {
    static func sector(at fraction: Double, rows: [StatsChartValue]) -> String? {
        guard fraction.isFinite, fraction >= 0, fraction <= 1 else { return nil }
        let positive = rows.filter { $0.amount.isFinite && $0.amount > 0 }
        let total = positive.reduce(0) { $0 + $1.amount }
        guard total > 0, total.isFinite else { return nil }
        let value = fraction * total
        var accumulated = 0.0
        for row in positive {
            accumulated += row.amount
            if value < accumulated { return row.name }
        }
        return positive.last?.name
    }
}

enum StatsDisplay {
    static func money(_ amount: Double, visible: Bool) -> String {
        visible ? String(format: "¥%.2f", amount) : "¥***"
    }
    static func chartAmount(_ amount: Double, total: Double, visible: Bool) -> Double {
        visible ? amount : (total > 0 ? amount / total * 100 : 0)
    }
}

enum StatsAggregates {
    static func fulfillmentRate(owned: Int, wished: Int) -> Double {
        let total = max(0, owned) + max(0, wished)
        return total > 0 ? Double(max(0, owned)) / Double(total) : 0
    }

    static func groupedDistribution(_ rows: [StatsChartValue], limit: Int = 10) -> [StatsChartValue] {
        guard limit > 0, rows.count > limit else { return rows }
        let remaining = rows.dropFirst(limit)
        var label = "其他"
        while rows.prefix(limit).contains(where: { $0.name == label }) { label += "（合并）" }
        return Array(rows.prefix(limit)) + [StatsChartValue(name: label, amount: remaining.reduce(0) { $0 + $1.amount },
            members: remaining.map(\.name))]
    }
    static func seasonSpending(_ rows: [StyleSpending]) -> [StyleSpending] {
        var totals: [String: Double] = [:]
        for row in rows {
            for season in ItemCollectionFilter.seasons(in: row.style) { totals[season, default: 0] += row.totalSpending }
        }
        return totals.map { StyleSpending(style: $0.key, totalSpending: $0.value) }
            .sorted { $0.totalSpending == $1.totalSpending ? $0.style < $1.style : $0.totalSpending > $1.totalSpending }
    }
}

private struct StatsCatalogFacts: Sendable {
    let references: [ItemReferencePrice]
    var categories: [Category]
    var prices: [Price]
    var payments: [Payment]
    var bindings: [OrderBinding]
    var stages: [PaymentStage]
}

@MainActor
final class StatsPageViewModel: ObservableObject {
    @Published private(set) var references: [ItemReferencePrice] = []
    @Published private(set) var items: [Item] = []
    @Published private(set) var outfitLogs: [OutfitLog] = []
    @Published private(set) var coordinates: [Coordinate] = []
    @Published private(set) var brands: [Brand] = []
    @Published private(set) var categories: [Category] = []
    @Published private(set) var prices: [Price] = []
    @Published private(set) var payments: [Payment] = []
    @Published private(set) var bindings: [OrderBinding] = []
    @Published private(set) var stages: [PaymentStage] = []
    @Published private(set) var spendingBySeason: [StyleSpending] = []
    @Published private(set) var totalSpending: Double = 0
    @Published private(set) var mostExpensive: ItemWithSpending? = nil
    @Published private(set) var spendingByBrand: [BrandSpending] = []
    @Published private(set) var spendingByCategory: [CategorySpending] = []
    @Published private(set) var spendingByStyle: [StyleSpending] = []
    @Published private(set) var monthlySpending: [MonthlySpending] = []
    @Published private(set) var wishlistBudget: Double = 0
    @Published private(set) var wishlistPriorityStats: [PriorityStats] = []

    private let db: DatabaseQueue
    private let coordinateRepo: CoordinateRepository
    private let brandRepo: BrandRepository
    private let itemRepo: ItemRepository
    private let outfitRepo: OutfitLogRepository
    private let priceRepo: PriceRepository

    init(db: DatabaseQueue = AppModule.shared.db.dbQueue) {
        self.db = db
        coordinateRepo = CoordinateRepository(db: db)
        brandRepo = BrandRepository(db: db)
        itemRepo = ItemRepository(db: db)
        outfitRepo = OutfitLogRepository(db: db)
        priceRepo = PriceRepository(db: db)
    }

    private var observationTasks: [Task<Void, Never>] = []

    func stopObserving() {
        observationTasks.forEach { $0.cancel() }
        observationTasks.removeAll()
    }

    func load() {
        guard observationTasks.isEmpty else { return }
        observationTasks.append(Task { [weak self, db] in
            for await facts in Self.observeCatalog(db: db) {
                guard !Task.isCancelled else { return }
                self?.categories = facts.categories
                self?.prices = facts.prices
                self?.payments = facts.payments
                self?.bindings = facts.bindings
                self?.stages = facts.stages
                self?.references = facts.references
            }
        })
        observationTasks.append(Task { [weak self, coordinateRepo] in
            for await value in coordinateRepo.observeAll() { guard !Task.isCancelled else { return }; self?.coordinates = value }
        })
        observationTasks.append(Task { [weak self, brandRepo] in
            for await value in brandRepo.observeAll() { guard !Task.isCancelled else { return }; self?.brands = value }
        })
        observationTasks.append(Task { [weak self, priceRepo] in
            for await value in priceRepo.getSpendingBySeason() { guard !Task.isCancelled else { return }; self?.spendingBySeason = StatsAggregates.seasonSpending(value) }
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

    nonisolated private static func observeCatalog(db: DatabaseQueue) -> AsyncStream<StatsCatalogFacts> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { @Sendable db in
                StatsCatalogFacts(references: try ItemReferencePrice.fetchAll(db), categories: try Category.fetchAll(db), prices: try Price.fetchAll(db), payments: try Payment.fetchAll(db),
                                  bindings: try OrderBinding.fetchAll(db), stages: try PaymentStage.fetchAll(db))
            }
            let token = observation.start(in: db, onError: { _ in continuation.finish() }, onChange: { continuation.yield($0) })
            continuation.onTermination = { _ in token.cancel() }
        }
    }

    func filteredItems(_ filter: StatsItemFilter) -> [Item] {
        filter.apply(to: items, brands: brands, categories: categories, prices: prices, payments: payments)
    }

    var spendingYears: [String] {
        let current = String(Calendar.current.component(.year, from: Date()))
        return Array(Set(monthlySpending.map { String($0.yearMonth.prefix(4)) } + [current])).sorted().reversed()
    }
    func trendSpending(year: String, quarters: Bool) -> [MonthlySpending] {
        let all = quarters ? quarterlySpending : monthlySpending
        guard year != "全部年份" else { return all }
        let amounts = Dictionary(uniqueKeysWithValues: all.map { ($0.yearMonth, $0.totalSpending) })
        return (1...(quarters ? 4 : 12)).map { number in
            let key = quarters ? "\(year)-Q\(number)" : String(format: "%@-%02d", year, number)
            return MonthlySpending(yearMonth: key, totalSpending: amounts[key] ?? 0)
        }
    }
    var pricesByItem: [Int64: Double] { OrderAccounting.displayAmounts(prices: prices, bindings: bindings, stages: stages, references: references) }

    var totalItems: Int { items.count }
    var ownedCount: Int { items.filter { $0.status == .owned }.count }
    var wishedCount: Int { items.filter { $0.status == .wished }.count }
    var pendingCount: Int { items.filter { $0.status == .pendingBalance }.count }
    var pendingPaymentCount: Int { items.filter { $0.status == .pendingPayment }.count }
    var pendingReviewCount: Int { items.filter { $0.status == .pendingReview }.count }
    var wishlistFulfillmentRate: Double { StatsAggregates.fulfillmentRate(owned: ownedCount, wished: wishedCount) }
    var totalCoordinates: Int { coordinates.count }
    var totalOutfits: Int { outfitLogs.count }

    var styleDistribution: [(String, Int)] {
        Dictionary(grouping: items) { $0.style?.isEmpty == false ? $0.style! : "未分类" }
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
        return Dictionary(grouping: items.filter { $0.status == .owned }, by: \.brandId)
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
