@preconcurrency import GRDB
import Foundation

final class SeasonRepository {
    private let db: DatabaseQueue
    init(db: DatabaseQueue) { self.db = db }

    func observeAll() -> AsyncStream<[Season]> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { db in
                try Season.order(Season.Columns.name).fetchAll(db)
            }
            let cancellable = observation.start(in: db) { error in
                print("SeasonRepository observeAll error: \(error)")
            } onChange: { seasons in
                continuation.yield(seasons)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    func getAll() async throws -> [Season] {
        try await db.read { db in try Season.order(Season.Columns.name).fetchAll(db) }
    }

    func insert(_ season: Season) async throws -> Season {
        try await db.write { db in
            var s = season
            try s.insert(db)
            return s
        }
    }

    func update(_ season: Season) async throws {
        try await db.write { db in
            var s = season
            try s.update(db)
        }
    }

    func delete(_ season: Season) async throws {
        try await db.write { db in try season.delete(db) }
    }
}
