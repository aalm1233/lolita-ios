import SwiftUI
@preconcurrency import GRDB

@MainActor
final class CoordinateDetailViewModel: ObservableObject {
    @Published private(set) var coordinate: Coordinate?
    @Published private(set) var items: [Item] = []
    @Published private(set) var allItems: [Item] = []
    @Published private(set) var pricesByItem: [Int64: [DetailPriceSummary]] = [:]
    @Published private(set) var brandNames: [Int64: String] = [:]
    @Published private(set) var categoryNames: [Int64: String] = [:]
    @Published private(set) var isLoading = true
    @Published private(set) var errorMessage: String?
    private let db: DatabaseQueue
    private let coordinateRepo: CoordinateRepository
    private let itemRepo: ItemRepository

    init(db: DatabaseQueue? = nil) {
        let queue = db ?? AppModule.shared.db.dbQueue
        self.db = queue
        self.coordinateRepo = CoordinateRepository(db: queue)
        self.itemRepo = ItemRepository(db: queue)
    }

    func load(coordinateId: Int64) async {
        if coordinate == nil { isLoading = true }
        errorMessage = nil
        defer { isLoading = false }
        do {
            guard let coordinate = try await coordinateRepo.getById(coordinateId) else {
                self.coordinate = nil
                errorMessage = "这个套装已被删除"
                return
            }
            async let loadedItems = coordinateRepo.getItems(for: coordinateId)
            async let loadedCatalog = DetailDataFactory.catalog(db: db)
            async let available = itemRepo.getAll()
            let (items, catalog, allItems) = try await (loadedItems, loadedCatalog, available)
            let prices = try await DetailDataFactory.prices(itemIds: items.map(\.id), db: db)
            guard !Task.isCancelled else { return }
            self.coordinate = coordinate
            self.items = items
            self.allItems = allItems.filter { $0.coordinateId == nil || $0.coordinateId == coordinateId }
            self.pricesByItem = prices
            self.brandNames = catalog.brandNames
            self.categoryNames = catalog.categoryNames
        } catch {
            if !Task.isCancelled { errorMessage = userFacingError(error) }
        }
    }

    var imageUrls: [URL] { coordinate?.imageUrls.values.filter { !$0.isEmpty }.map { ImageFileHelper.fileURL(for: $0) } ?? [] }
    var totalPrice: Double { pricesByItem.values.flatMap { $0 }.reduce(0) { $0 + $1.price.totalPrice } }
    var paidAmount: Double { pricesByItem.values.flatMap { $0 }.reduce(0) { $0 + $1.paidAmount } }
    var unpaidAmount: Double { pricesByItem.values.flatMap { $0 }.reduce(0) { $0 + $1.unpaidAmount } }

    func saveItems(_ itemIds: [Int64]) async throws {
        guard let coordinate else { throw ValidationError.invalid("套装已不存在") }
        _ = try await coordinateRepo.save(coordinate, itemIds: itemIds)
        await load(coordinateId: coordinate.id)
    }

    func delete() async throws {
        guard let coordinate else { return }
        try await coordinateRepo.delete(coordinate)
    }
}
