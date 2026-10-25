@preconcurrency import GRDB
import Foundation

final class ItemRepository: Sendable {
    private let db: DatabaseQueue
    init(db: DatabaseQueue) { self.db = db }

    func observeAll() -> AsyncStream<[Item]> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { db in
                try Item.order(Item.Columns.updatedAt.desc).fetchAll(db)
            }
            let cancellable = observation.start(in: db) { error in
                print("ItemRepository observeAll error: \(error)")
            } onChange: { items in
                continuation.yield(items)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    func getAll() async throws -> [Item] {
        try await db.read { db in try Item.order(Item.Columns.updatedAt.desc).fetchAll(db) }
    }

    func getById(_ id: Int64) async throws -> Item? {
        try await db.read { db in try Item.fetchOne(db, key: id) }
    }

    func getByStatus(_ status: ItemStatus) async throws -> [Item] {
        try await db.read { db in
            try Item.filter(Item.Columns.status == status)
                .order(Item.Columns.updatedAt.desc).fetchAll(db)
        }
    }

    func getByCoordinate(_ coordinateId: Int64) async throws -> [Item] {
        try await db.read { db in
            try Item.filter(Item.Columns.coordinateId == coordinateId)
                .order(Item.Columns.coordinateOrder).fetchAll(db)
        }
    }

    func getByLocation(_ locationId: Int64) async throws -> [Item] {
        try await db.read { db in
            try Item.filter(Item.Columns.locationId == locationId).fetchAll(db)
        }
    }

    func insert(_ item: Item, clearingDraft: String? = nil) async throws -> Item {
        try await db.write { db in
            var i = item
            i.name = try InputValidation.name(i.name)
            try StorageRepository.validatePlacement(db, item: i, previous: try Item.fetchOne(db, key: i.id))
            try Self.validateParent(db, item: i)
            try i.insert(db)
            if let clearingDraft { try ItemDraft.deleteOne(db, key: clearingDraft) }
            if i.includedInParentPrice, let parent = i.parentItemId { try OrderRepository.refreshStatuses(db, itemId: parent) }
            return i
        }
    }

    func update(_ item: Item, clearingDraft: String? = nil, expectedUpdatedAt: Int64? = nil) async throws {
        try await db.write { db in
            if let expectedUpdatedAt { guard try Item.fetchOne(db, key: item.id)?.updatedAt == expectedUpdatedAt else { throw ValidationError.invalid("物品已在其他页面更改，草稿已保留，请重新核对") } }
            var i = item
            i.name = try InputValidation.name(i.name)
            try StorageRepository.validatePlacement(db, item: i, previous: try Item.fetchOne(db, key: i.id))
            try Self.validateParent(db, item: i)
            if i.status == .wished, try OrderBinding.fetchOne(db, key: i.id) != nil,
               try Item.fetchOne(db, key: i.id)?.status != .wished {
                throw ValidationError.invalid("请先归档当前订单，再将物品移回心愿")
            }
            i.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
            try i.update(db)
            if let clearingDraft { try ItemDraft.deleteOne(db, key: clearingDraft) }
            try Self.refreshPaymentStatus(db, itemId: i.id)
            if i.includedInParentPrice, let parent = i.parentItemId { try OrderRepository.refreshStatuses(db, itemId: parent) }
        }
    }

    func delete(_ item: Item) async throws {
        let draftImages = try await db.read { db in try ItemDraft.filter(Column("targetItemId") == item.id).fetchAll(db).flatMap(\.allImagePaths) + ItemSourceRecord.filter(Column("itemId") == item.id).fetchAll(db).flatMap { $0.imagePaths.values } }
        try await db.write { @Sendable db in
            try db.execute(sql: "DELETE FROM orderBindings WHERE itemId = ?", arguments: [item.id])
            try item.delete(db)
        }
        try? ImageFileHelper.deleteUnreferenced(paths: item.allImagePaths + draftImages, db: db)
    }
}

// Keep derived status updates in the same transaction as payment/price mutations.
extension ItemRepository {
    private static func validateParent(_ db: Database, item: Item) throws {
        guard let parentId = item.parentItemId else {
            guard !item.includedInParentPrice else { throw ValidationError.invalid("共价小物必须选择主件") }
            return
        }
        guard parentId != item.id, let parent = try Item.fetchOne(db, key: parentId), parent.parentItemId == nil,
              try Item.filter(Column("parentItemId") == item.id).fetchCount(db) == 0 else {
            throw ValidationError.invalid("主件不存在或会形成多层、循环关联")
        }
        if item.includedInParentPrice {
            guard try Price.filter(Price.Columns.itemId == item.id).fetchCount(db) == 0,
                  try ItemReferencePrice.fetchOne(db, key: item.id) == nil else {
                throw ValidationError.invalid("小物已有独立账本或参考价，不能直接改为共价；请保留或先核对独立记录")
            }
        }
    }

    static func refreshPaymentStatus(_ db: Database, itemId: Int64) throws {
        if try OrderBinding.fetchOne(db, key: itemId) != nil {
            try OrderRepository.refreshStatuses(db, itemId: itemId)
            return
        }
        guard let item = try Item.fetchOne(db, key: itemId), item.status != .wished else { return }
        let unpaid = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM payments pay JOIN prices pr ON pay.priceId = pr.id
            WHERE pr.itemId = ? AND pr.type = 'DEPOSIT_BALANCE' AND pay.isPaid = 0
            """, arguments: [itemId]) ?? 0
        let status: ItemStatus = unpaid > 0 ? .pendingBalance : .owned
        guard item.status != status else { return }
        try db.execute(sql: "UPDATE items SET status = ?, updatedAt = ? WHERE id = ?", arguments: [status.rawValue, Int64(Date().timeIntervalSince1970 * 1000), itemId])
    }
}
