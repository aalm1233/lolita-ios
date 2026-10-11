import SwiftUI
@preconcurrency import GRDB

enum OutfitLogDetailDataFactory {
    nonisolated static func removeItem(db: DatabaseQueue, logId: Int64, itemId: Int64) async throws {
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        try await db.write { @Sendable db in
            guard var log = try OutfitLog.fetchOne(db, key: logId) else { throw ValidationError.invalid("穿搭记录已被删除") }
            try OutfitItemCrossRef.filter(OutfitItemCrossRef.Columns.outfitLogId == logId)
                .filter(OutfitItemCrossRef.Columns.itemId == itemId).deleteAll(db)
            log.updatedAt = timestamp
            try log.update(db)
        }
    }
}

@MainActor
final class OutfitLogDetailViewModel: ObservableObject {
    @Published private(set) var log: OutfitLog?
    @Published private(set) var items: [Item] = []
    @Published private(set) var brandNames: [Int64: String] = [:]
    @Published private(set) var categoryNames: [Int64: String] = [:]
    @Published private(set) var isLoading = true
    @Published private(set) var errorMessage: String?
    private let db: DatabaseQueue
    private let repo: OutfitLogRepository
    private let itemRepo: ItemRepository

    init(db: DatabaseQueue? = nil) {
        let queue = db ?? AppModule.shared.db.dbQueue
        self.db = queue
        self.repo = OutfitLogRepository(db: queue)
        self.itemRepo = ItemRepository(db: queue)
    }

    func load(logId: Int64) async {
        if log == nil { isLoading = true }
        errorMessage = nil
        defer { isLoading = false }
        do {
            guard let log = try await repo.getById(logId) else { self.log = nil; errorMessage = "这条穿搭记录已被删除"; return }
            async let loadedIds = repo.getItemIds(for: logId)
            async let loadedItems = itemRepo.getAll()
            async let loadedCatalog = DetailDataFactory.catalog(db: db)
            let (ids, allItems, catalog) = try await (loadedIds, loadedItems, loadedCatalog)
            let order = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($0.element, $0.offset) })
            guard !Task.isCancelled else { return }
            self.log = log
            self.items = allItems.filter { order[$0.id] != nil }.sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
            self.brandNames = catalog.brandNames
            self.categoryNames = catalog.categoryNames
        } catch {
            if !Task.isCancelled { errorMessage = userFacingError(error) }
        }
    }

    var imageUrls: [URL] { log?.imageUrls.values.filter { !$0.isEmpty }.map { ImageFileHelper.fileURL(for: $0) } ?? [] }

    func removeItem(_ itemId: Int64) async throws {
        guard let log else { throw ValidationError.invalid("穿搭记录已不存在") }
        try await OutfitLogDetailDataFactory.removeItem(db: db, logId: log.id, itemId: itemId)
        await load(logId: log.id)
    }

    func delete() async throws {
        guard let log else { return }
        try await repo.delete(log)
    }
}
