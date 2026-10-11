@preconcurrency import GRDB
import Foundation

final class SourceRepository: Sendable {
    private let db: DatabaseQueue
    init(db: DatabaseQueue) { self.db = db }

    func observeAll() -> AsyncStream<[Source]> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { db in
                try Source.order(Source.Columns.name).fetchAll(db)
            }
            let cancellable = observation.start(in: db) { error in
                print("SourceRepository observeAll error: \(error)")
            } onChange: { sources in
                continuation.yield(sources)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    func getAll() async throws -> [Source] {
        try await db.read { db in try Source.order(Source.Columns.name).fetchAll(db) }
    }

    func insert(_ source: Source) async throws -> Source {
        try await db.write { db in
            var s = source
            try s.insert(db)
            return s
        }
    }

    func update(_ source: Source) async throws {
        try await db.write { db in
            let old = try Source.fetchOne(db, key: source.id)
            var s = source
            s.name = try InputValidation.name(s.name)
            try s.update(db)
            if let old, old.name != s.name {
                try db.execute(sql: "UPDATE items SET source = ?, updatedAt = ? WHERE source = ?", arguments: [s.name, Int64(Date().timeIntervalSince1970 * 1000), old.name])
            }
        }
    }

    func delete(_ source: Source) async throws {
        try await db.write { db in
            try db.execute(sql: "UPDATE items SET source = NULL, updatedAt = ? WHERE source = ?", arguments: [Int64(Date().timeIntervalSince1970 * 1000), source.name])
            try source.delete(db)
        }
    }
}
