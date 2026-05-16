@preconcurrency import GRDB
import Foundation

final class SourceRepository {
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
            var s = source
            try s.update(db)
        }
    }

    func delete(_ source: Source) async throws {
        try await db.write { db in try source.delete(db) }
    }
}
