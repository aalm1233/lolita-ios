import SwiftUI
@preconcurrency import GRDB

/// Batch membership changes are atomic and only update placement-related fields.
enum LocationDetailDataFactory {
    nonisolated static func saveMembership(db: DatabaseQueue, locationId: Int64, originalIds: Set<Int64>, selectedIds: Set<Int64>) async throws {
        let addedIds = selectedIds.subtracting(originalIds)
        let removedIds = originalIds.subtracting(selectedIds)
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        try await db.write { @Sendable db in
            guard locationId > 0, try Location.fetchOne(db, key: locationId) != nil else { throw ValidationError.invalid("收纳位置已被删除") }
            for id in addedIds {
                guard var item = try Item.fetchOne(db, key: id) else { throw ValidationError.invalid("选中的服饰已被删除") }
                guard try StorageRepository.isOwned(db, item: item) else { throw ValidationError.invalid("仅已拥有物品可以收纳") }
                item.storageNodeId = nil
                item.locationId = locationId
                item.updatedAt = timestamp
                try item.update(db)
            }
            for id in removedIds {
                guard var item = try Item.fetchOne(db, key: id), item.locationId == locationId else { continue }
                item.storageNodeId = nil
                item.locationId = nil
                item.updatedAt = timestamp
                try item.update(db)
            }
        }
    }

    nonisolated static func assignUnassigned(db: DatabaseQueue, itemIds: Set<Int64>, locationId: Int64) async throws {
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        try await db.write { @Sendable db in
            guard locationId > 0, try Location.fetchOne(db, key: locationId) != nil else { throw ValidationError.invalid("请选择有效的收纳位置") }
            for id in itemIds {
                guard var item = try Item.fetchOne(db, key: id) else { throw ValidationError.invalid("选中的服饰已被删除") }
                guard item.locationId == nil else { throw ValidationError.invalid("\(item.name)已经放入其他位置，请刷新后再试") }
                guard try StorageRepository.isOwned(db, item: item) else { throw ValidationError.invalid("仅已拥有物品可以收纳") }
                item.storageNodeId = nil
                item.locationId = locationId
                item.updatedAt = timestamp
                try item.update(db)
            }
        }
    }
}

@MainActor
final class LocationDetailViewModel: ObservableObject {
    @Published private(set) var location: Location?
    @Published private(set) var items: [Item] = []
    @Published private(set) var allItems: [Item] = []
    @Published private(set) var locations: [Location] = []
    @Published private(set) var brandNames: [Int64: String] = [:]
    @Published private(set) var categoryNames: [Int64: String] = [:]
    @Published private(set) var locationNames: [Int64: String] = [:]
    @Published private(set) var isLoading = true
    @Published private(set) var errorMessage: String?
    let locationId: Int64
    private let db: DatabaseQueue
    private let locationRepo: LocationRepository
    private let itemRepo: ItemRepository

    init(locationId: Int64, db: DatabaseQueue? = nil) {
        let queue = db ?? AppModule.shared.db.dbQueue
        self.locationId = locationId
        self.db = queue
        self.locationRepo = LocationRepository(db: queue)
        self.itemRepo = ItemRepository(db: queue)
    }

    var isUnassigned: Bool { locationId == -1 }
    var title: String { isUnassigned ? "未分配" : location?.name ?? "位置详情" }

    func load() async {
        if items.isEmpty { isLoading = true }
        errorMessage = nil
        defer { isLoading = false }
        do {
            let location = isUnassigned ? nil : try await locationRepo.getById(locationId)
            if !isUnassigned, location == nil { errorMessage = "这个收纳位置已被删除"; self.location = nil; return }
            async let loadedItems = itemRepo.getAll()
            async let loadedCatalog = DetailDataFactory.catalog(db: db)
            let (allItems, catalog) = try await (loadedItems, loadedCatalog)
            guard !Task.isCancelled else { return }
            self.location = location
            self.allItems = allItems
            self.items = allItems.filter { isUnassigned ? $0.locationId == nil : $0.locationId == locationId }
            self.locations = catalog.locations
            self.brandNames = catalog.brandNames
            self.categoryNames = catalog.categoryNames
            self.locationNames = catalog.locationNames
        } catch {
            if !Task.isCancelled { errorMessage = userFacingError(error) }
        }
    }

    func saveMembership(_ itemIds: Set<Int64>) async throws {
        guard !isUnassigned else { throw ValidationError.invalid("请为未分配服饰选择收纳位置") }
        try await LocationDetailDataFactory.saveMembership(db: db, locationId: locationId,
                                                           originalIds: Set(items.map(\.id)), selectedIds: itemIds)
        await load()
    }

    func assign(_ itemIds: Set<Int64>, to destinationId: Int64) async throws {
        guard isUnassigned else { throw ValidationError.invalid("请从未分配列表选择服饰") }
        try await LocationDetailDataFactory.assignUnassigned(db: db, itemIds: itemIds, locationId: destinationId)
        await load()
    }

    func delete() async throws {
        guard let location else { return }
        try await locationRepo.delete(location, clearContents: true)
    }
}
