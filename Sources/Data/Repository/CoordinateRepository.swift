@preconcurrency import GRDB
import Foundation

final class CoordinateRepository: Sendable {
    private let db: DatabaseQueue
    init(db: DatabaseQueue) { self.db = db }

    func observeAll() -> AsyncStream<[Coordinate]> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { db in
                try Coordinate.order(Coordinate.Columns.createdAt.desc).fetchAll(db)
            }
            let cancellable = observation.start(in: db) { error in
                print("CoordinateRepository observeAll error: \(error)")
            } onChange: { coordinates in
                continuation.yield(coordinates)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    func getAll() async throws -> [Coordinate] {
        try await db.read { db in try Coordinate.order(Coordinate.Columns.createdAt.desc).fetchAll(db) }
    }

    func getById(_ id: Int64) async throws -> Coordinate? {
        try await db.read { db in try Coordinate.fetchOne(db, key: id) }
    }

    func getItems(for coordinateId: Int64) async throws -> [Item] {
        try await db.read { db in
            try Item.filter(Item.Columns.coordinateId == coordinateId)
                .order(Item.Columns.coordinateOrder).fetchAll(db)
        }
    }

    func insert(_ coordinate: Coordinate) async throws -> Coordinate {
        try await db.write { db in
            var c = coordinate
            try c.insert(db)
            return c
        }
    }

    func update(_ coordinate: Coordinate) async throws {
        try await db.write { db in
            var c = coordinate
            c.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
            try c.update(db)
        }
    }

    func delete(_ coordinate: Coordinate) async throws {
        try await db.write { db in
            try db.execute(sql: "UPDATE items SET coordinateId = NULL, coordinateOrder = 0 WHERE coordinateId = ?", arguments: [coordinate.id])
            try coordinate.delete(db)
        }
        try? ImageFileHelper.deleteUnreferenced(paths: coordinate.imageUrls.values, db: db)
    }
}

extension CoordinateRepository {
    func save(_ coordinate: Coordinate, itemIds: [Int64]) async throws -> Coordinate {
        try await db.write { db in
            var value = coordinate
            value.name = try InputValidation.name(value.name)
            value.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
            if value.id == 0 { try value.insert(db) } else { try value.update(db) }
            var seen = Set<Int64>()
            let ids = itemIds.filter { seen.insert($0).inserted }
            try db.execute(sql: "UPDATE items SET coordinateId = NULL, coordinateOrder = 0, updatedAt = ? WHERE coordinateId = ?", arguments: [value.updatedAt, value.id])
            for (order, id) in ids.enumerated() {
                guard let item = try Item.fetchOne(db, key: id) else { throw ValidationError.invalid("选中的服饰已被删除") }
                guard item.coordinateId == nil || item.coordinateId == value.id else { throw ValidationError.invalid("\(item.name)已属于其他套装，请先解除关联") }
                try db.execute(sql: "UPDATE items SET coordinateId = ?, coordinateOrder = ?, updatedAt = ? WHERE id = ?", arguments: [value.id, order, value.updatedAt, id])
            }
            return value
        }
    }
}
