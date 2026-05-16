@preconcurrency import GRDB
import Foundation

final class LocationRepository {
    private let db: DatabaseQueue
    init(db: DatabaseQueue) { self.db = db }

    func observeAll() -> AsyncStream<[Location]> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { db in
                try Location.order(Location.Columns.sortOrder, Location.Columns.name).fetchAll(db)
            }
            let cancellable = observation.start(in: db) { error in
                print("LocationRepository observeAll error: \(error)")
            } onChange: { locations in
                continuation.yield(locations)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    func getAll() async throws -> [Location] {
        try await db.read { db in try Location.order(Location.Columns.sortOrder, Location.Columns.name).fetchAll(db) }
    }

    func getById(_ id: Int64) async throws -> Location? {
        try await db.read { db in try Location.fetchOne(db, key: id) }
    }

    func insert(_ location: Location) async throws -> Location {
        try await db.write { db in
            var l = location
            try l.insert(db)
            return l
        }
    }

    func update(_ location: Location) async throws {
        try await db.write { db in
            var l = location
            l.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
            try l.update(db)
        }
    }

    func delete(_ location: Location) async throws {
        try await db.write { db in try location.delete(db) }
    }
}
