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

    func insert(_ item: Item) async throws -> Item {
        try await db.write { db in
            var i = item
            i.name = try InputValidation.name(i.name)
            try i.insert(db)
            return i
        }
    }

    func update(_ item: Item) async throws {
        try await db.write { db in
            var i = item
            i.name = try InputValidation.name(i.name)
            i.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
            try i.update(db)
            try Self.refreshPaymentStatus(db, itemId: i.id)
        }
    }

    func delete(_ item: Item) async throws {
        try await db.write { db in try item.delete(db) }
        try? ImageFileHelper.deleteUnreferenced(paths: item.imageUrls.values + [item.sizeChartImageUrl].compactMap { $0 }, db: db)
    }
}

// Keep derived status updates in the same transaction as payment/price mutations.
extension ItemRepository {
    static func refreshPaymentStatus(_ db: Database, itemId: Int64) throws {
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
