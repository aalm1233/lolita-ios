import SwiftUI
@preconcurrency import GRDB

struct DetailPriceSummary: Identifiable, Sendable {
    let price: Price
    let payments: [Payment]
    var stages: [PaymentStage] = []
    var isCurrent = false
    var id: Int64 { price.id }
    var paidAmount: Double { payments.filter(\.isPaid).reduce(0) { $0 + $1.amount } }
    var unpaidAmount: Double {
        if isCurrent && price.purchaseRecordStatus == .tracked { return max(0, price.totalPrice - paidAmount) }
        if !stages.isEmpty { return 0 }
        return payments.filter { !$0.isPaid }.reduce(0) { $0 + $1.amount }
    }
    var firstPaidDate: Int64? { payments.compactMap { $0.isPaid ? $0.paidDate : nil }.min() }
}

struct DetailCatalog: Sendable {
    let brands: [Brand]
    let categories: [Category]
    let locations: [Location]
    var brandNames: [Int64: String] { Dictionary(uniqueKeysWithValues: brands.map { ($0.id, $0.name) }) }
    var categoryNames: [Int64: String] { Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) }) }
    var locationNames: [Int64: String] { Dictionary(uniqueKeysWithValues: locations.map { ($0.id, $0.name) }) }
}

/// Queries are created outside UI isolation; view models only consume the resulting values.
enum DetailDataFactory {
    nonisolated static func catalog(db: DatabaseQueue) async throws -> DetailCatalog {
        try await db.read { @Sendable db in
            DetailCatalog(brands: try Brand.fetchAll(db), categories: try Category.fetchAll(db),
                          locations: try Location.order(Location.Columns.sortOrder, Location.Columns.name).fetchAll(db))
        }
    }

    nonisolated static func prices(itemIds: [Int64], db: DatabaseQueue) async throws -> [Int64: [DetailPriceSummary]] {
        guard !itemIds.isEmpty else { return [:] }
        return try await db.read { @Sendable db in
            let prices = try Price.filter(itemIds.contains(Price.Columns.itemId)).order(Price.Columns.createdAt.desc).fetchAll(db)
            let priceIds = prices.map(\.id)
            let payments = try Payment.filter(priceIds.contains(Payment.Columns.priceId)).order(Payment.Columns.dueDate).fetchAll(db)
            let paymentsByPrice = Dictionary(grouping: payments, by: \.priceId)
            let stages = Dictionary(grouping: try PaymentStage.fetchAll(db), by: \.priceId)
            let current = Set(try OrderBinding.fetchAll(db).map(\.priceId))
            return Dictionary(grouping: prices.map { DetailPriceSummary(price: $0, payments: paymentsByPrice[$0.id] ?? [],
                stages: stages[$0.id] ?? [], isCurrent: current.contains($0.id)) }, by: { $0.price.itemId })
        }
    }
}

struct DetailRecommendationGroup: Identifiable {
    let name: String
    let matches: [MatchScore]
    var id: String { name }
}

@MainActor
final class ItemDetailViewModel: ObservableObject {
    @Published private(set) var reference: ItemReferencePrice?
    @Published private(set) var ownerId: Int64 = 0
    @Published private(set) var item: Item?
    @Published private(set) var brandName = ""
    @Published private(set) var categoryName = ""
    @Published private(set) var semantic: CategorySemantic = .unconfirmed
    @Published private(set) var locationName = ""
    @Published private(set) var coordinate: Coordinate?
    @Published private(set) var prices: [DetailPriceSummary] = []
    @Published private(set) var recommendations: [MatchScore] = []
    @Published private(set) var isLoading = true
    @Published private(set) var isLoadingRecommendations = false
    @Published private(set) var errorMessage: String?
    private var catalog: DetailCatalog?

    let itemId: Int64
    private let db: DatabaseQueue
    private let itemRepo: ItemRepository
    private let coordinateRepo: CoordinateRepository
    private let recRepo: RecommendationRepository

    init(itemId: Int64, db: DatabaseQueue? = nil) {
        let queue = db ?? AppModule.shared.db.dbQueue
        self.itemId = itemId
        self.db = queue
        self.itemRepo = ItemRepository(db: queue)
        self.coordinateRepo = CoordinateRepository(db: queue)
        self.recRepo = RecommendationRepository(db: queue)
    }

    func load() async {
        if item == nil { isLoading = true }
        errorMessage = nil
        defer { isLoading = false }
        do {
            guard let value = try await itemRepo.getById(itemId) else {
                item = nil
                errorMessage = "这件服饰已被删除"
                return
            }
            async let loadedCatalog = DetailDataFactory.catalog(db: db)
            let owner = try await OrderRepository(db: db).owner(itemId: itemId)
            self.ownerId = owner.id
            reference = try await AfterSaleRepository(db: db).reference(itemId: owner.id)
            async let loadedPrices = DetailDataFactory.prices(itemIds: [owner.id], db: db)
            let (catalog, prices) = try await (loadedCatalog, loadedPrices)
            let coordinate = if let id = value.coordinateId { try await coordinateRepo.getById(id) } else { nil as Coordinate? }
            guard !Task.isCancelled else { return }
            self.item = value
            self.catalog = catalog
            self.prices = prices[owner.id] ?? []
            self.coordinate = coordinate
            brandName = catalog.brandNames[value.brandId] ?? "未知品牌"
            categoryName = catalog.categoryNames[value.categoryId] ?? "未分类"
            semantic = catalog.categories.first(where: { $0.id == value.categoryId })?.categorySemantic ?? .unconfirmed
            let nodes = try await StorageRepository(db: db).getAll()
            locationName = StorageTree.path(roomId: value.locationId, nodeId: value.storageNodeId, rooms: catalog.locations, nodes: nodes)
        } catch {
            if !Task.isCancelled { errorMessage = userFacingError(error) }
        }
    }

    func loadRecommendations() async {
        guard let item else { return }
        isLoadingRecommendations = true
        defer { isLoadingRecommendations = false }
        do {
            let values = try await recRepo.getRecommendations(for: item, topN: Int.max)
            guard !Task.isCancelled else { return }
            recommendations = values
        } catch {
            if !Task.isCancelled { errorMessage = userFacingError(error) }
        }
    }

    var recommendationGroups: [DetailRecommendationGroup] {
        let names = catalog?.categoryNames ?? [:]
        let groups = Dictionary(grouping: recommendations) { names[$0.item.categoryId] ?? "其他" }
        return groups.map { DetailRecommendationGroup(name: $0.key, matches: $0.value) }
            .sorted {
                let first = $0.matches.first?.score ?? 0
                let second = $1.matches.first?.score ?? 0
                return first == second ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : first > second
            }
    }

    var imageUrls: [URL] {
        item?.imageUrls.values.filter { !$0.isEmpty }.map { ImageFileHelper.fileURL(for: $0) } ?? []
    }
    var brandLogoPath: String? {
        guard let item else { return nil }
        return catalog?.brands.first { $0.id == item.brandId }?.logoUrl
    }
    var totalPrice: Double { prices.reduce(0) { $0 + $1.price.totalPrice } }
    var paidAmount: Double { prices.reduce(0) { $0 + $1.paidAmount } }
    var unpaidAmount: Double { prices.reduce(0) { $0 + $1.unpaidAmount } }

    func deleteItem() async throws {
        guard let item else { return }
        try await itemRepo.delete(item)
    }
}
