@preconcurrency import GRDB
import Foundation

final class CoordinateRepository {
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
        try await db.write { db in try coordinate.delete(db) }
    }
}
