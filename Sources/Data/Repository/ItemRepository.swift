@preconcurrency import GRDB
import Foundation

final class ItemRepository {
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
            try i.insert(db)
            return i
        }
    }

    func update(_ item: Item) async throws {
        try await db.write { db in
            var i = item
            i.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
            try i.update(db)
        }
    }

    func delete(_ item: Item) async throws {
        try await db.write { db in try item.delete(db) }
    }
}
