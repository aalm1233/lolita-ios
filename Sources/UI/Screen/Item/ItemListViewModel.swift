import SwiftUI
@preconcurrency import GRDB

enum ItemSubTab: String, CaseIterable {
    case location = "位置"
    case items = "服饰"
    case coordinate = "套装"
    case wishlist = "心愿"
}

/// The same filters feed every item presentation, so switching layouts cannot change results.
struct ItemCollectionFilter {
    var brandId: Int64?
    var categoryId: Int64?
    var status: ItemStatus?
    var group: CategoryGroup?
    var season: String?
    var style: String?
    var color: String?
    var search = ""

    static func seasons(in value: String?) -> [String] {
        (value ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    func apply(to items: [Item], categories: [Category], collection: ItemStatus, newestFirst: Bool,
               sort: CollectionSortOption? = nil, prices: [Int64: Double] = [:]) -> [Item] {
        let categoryGroups = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.group) })
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = items.filter { item in
            let inCollection = collection == .owned ? item.status != .wished : item.status == collection
            return inCollection && (brandId == nil || item.brandId == brandId)
                && (categoryId == nil || item.categoryId == categoryId)
                && (status == nil || item.status == status)
                && (group == nil || categoryGroups[item.categoryId] == group)
                && (season.map { Self.seasons(in: item.season).contains($0) } ?? true)
                && (style == nil || item.style == style)
                && (color.map { item.colors.values.contains($0) } ?? true)
                && (query.isEmpty || item.name.localizedCaseInsensitiveContains(query))
        }
        return (sort ?? (newestFirst ? .updatedNewest : .nameAscending)).sorted(filtered) {
            CollectionSortKey(id: $0.id, name: $0.name, updatedAt: $0.updatedAt, price: prices[$0.id] ?? 0)
        }
    }
}

private struct CollectionFacts: Sendable {
    var references: [ItemReferencePrice]
    var prices: [Price]
    var outfitItems: [OutfitItemCrossRef]
    var logs: [OutfitLog]
    var bindings: [OrderBinding]
    var stages: [PaymentStage]
}

@MainActor
final class ItemListViewModel: ObservableObject {
    @Published private(set) var items: [Item] = []
    @Published private(set) var locations: [Location] = []
    @Published private(set) var coordinates: [Coordinate] = []
    @Published private(set) var isLoading = true
    @Published private(set) var pricesByItem: [Int64: Double] = [:]
    @Published private var outfitItems: [OutfitItemCrossRef] = []
    @Published private var logs: [OutfitLog] = []
    @Published var brands: [Brand] = []
    @Published var categories: [Category] = []
    @Published var brandFilter: Int64?
    @Published var categoryFilter: Int64?
    @Published var statusFilter: ItemStatus?
    @Published var groupFilter: CategoryGroup?
    @Published var seasonFilter: String?
    @Published var styleFilter: String?
    @Published var colorFilter: String?
    @Published var searchText = ""
    @Published var sortOption: CollectionSortOption = .updatedNewest
    @Published var selectedSubTab: ItemSubTab = .items

    private let db: DatabaseQueue
    private let itemRepo: ItemRepository
    private let locationRepo: LocationRepository
    private let coordinateRepo: CoordinateRepository
    private var observationTasks: [Task<Void, Never>] = []

    init(db: DatabaseQueue = AppModule.shared.db.dbQueue) {
        self.db = db
        itemRepo = ItemRepository(db: db)
        locationRepo = LocationRepository(db: db)
        coordinateRepo = CoordinateRepository(db: db)
    }

    func stopObserving() {
        observationTasks.forEach { $0.cancel() }
        observationTasks.removeAll()
    }

    func load() {
        guard observationTasks.isEmpty else { return }
        observationTasks.append(Task { [weak self, db] in
            let metadata = try? await db.read { @Sendable db in
                (try Brand.order(Brand.Columns.name).fetchAll(db), try Category.order(Category.Columns.name).fetchAll(db))
            }
            guard !Task.isCancelled else { return }
            self?.brands = metadata?.0 ?? []
            self?.categories = metadata?.1 ?? []
        })
        observationTasks.append(Task { [weak self, itemRepo] in
            for await items in itemRepo.observeAll() {
                guard !Task.isCancelled else { return }
                self?.items = items
                self?.isLoading = false
            }
        })
        observationTasks.append(Task { [weak self, locationRepo] in
            for await locations in locationRepo.observeAll() { guard !Task.isCancelled else { return }; self?.locations = locations }
        })
        observationTasks.append(Task { [weak self, coordinateRepo] in
            for await coordinates in coordinateRepo.observeAll() { guard !Task.isCancelled else { return }; self?.coordinates = coordinates }
        })
        observationTasks.append(Task { [weak self, db] in
            for await facts in Self.observeFacts(db: db) {
                guard !Task.isCancelled else { return }
                self?.pricesByItem = OrderAccounting.displayAmounts(prices: facts.prices, bindings: facts.bindings, stages: facts.stages, references: facts.references)
                self?.outfitItems = facts.outfitItems
                self?.logs = facts.logs
            }
        })
    }

    // Create tracking outside the main actor; GRDB evaluates it on its own queue.
    nonisolated private static func observeFacts(db: DatabaseQueue) -> AsyncStream<CollectionFacts> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { @Sendable db in
                CollectionFacts(references: try ItemReferencePrice.fetchAll(db), prices: try Price.fetchAll(db), outfitItems: try OutfitItemCrossRef.fetchAll(db), logs: try OutfitLog.fetchAll(db),
                                bindings: try OrderBinding.fetchAll(db), stages: try PaymentStage.fetchAll(db))
            }
            let token = observation.start(in: db, onError: { _ in continuation.finish() }, onChange: { continuation.yield($0) })
            continuation.onTermination = { _ in token.cancel() }
        }
    }

    var activeFilterCount: Int {
        [brandFilter != nil, categoryFilter != nil, statusFilter != nil, groupFilter != nil,
         seasonFilter != nil, styleFilter != nil, colorFilter != nil].filter { $0 }.count
    }

    var availableSeasons: [String] { Array(Set(items.flatMap { ItemCollectionFilter.seasons(in: $0.season) })).sorted() }
    var availableStyles: [String] { Array(Set(items.compactMap(\.style).filter { !$0.isEmpty })).sorted() }
    var availableColors: [String] { Array(Set(items.flatMap { $0.colors.values })).sorted() }

    func resetFilters() {
        brandFilter = nil; categoryFilter = nil; statusFilter = nil; groupFilter = nil
        seasonFilter = nil; styleFilter = nil; colorFilter = nil
    }

    func itemsByStatus(_ status: ItemStatus) -> [Item] {
        ItemCollectionFilter(brandId: brandFilter, categoryId: categoryFilter, status: statusFilter,
                             group: groupFilter, season: seasonFilter, style: styleFilter, color: colorFilter, search: searchText)
            .apply(to: items, categories: categories, collection: status, newestFirst: true, sort: sortOption, prices: pricesByItem)
    }

    func wishlistByPriority() -> [Item] {
        itemsByStatus(.wished).sorted {
            let ranks: [ItemPriority: Int] = [.high: 0, .medium: 1, .low: 2]
            if ranks[$0.priority] != ranks[$1.priority] { return ranks[$0.priority]! < ranks[$1.priority]! }
            return $0.updatedAt == $1.updatedAt ? $0.id > $1.id : $0.updatedAt > $1.updatedAt
        }
    }

    func itemsByLocation(_ locationId: Int64) -> [Item] { items.filter { $0.locationId == locationId } }
    func itemsByCoordinate(_ coordinateId: Int64) -> [Item] {
        items.filter { $0.coordinateId == coordinateId }.sorted { $0.coordinateOrder < $1.coordinateOrder }
    }
    func itemsByOutfit(_ logId: Int64) -> [Item] {
        let ids = Set(outfitItems.filter { $0.outfitLogId == logId }.map(\.itemId))
        return items.filter { ids.contains($0.id) }
    }
    func totalPrice(of items: [Item]) -> Double { items.reduce(0) { $0 + (pricesByItem[$1.id] ?? 0) } }
    var todayOutfit: OutfitLog? {
        logs.filter { Calendar.current.isDateInToday(Date(timeIntervalSince1970: TimeInterval($0.date) / 1000)) }.max { $0.date < $1.date }
    }
    func delete(_ item: Item) async throws { try await itemRepo.delete(item) }
}
