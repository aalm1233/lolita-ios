@preconcurrency import GRDB
import Foundation

final class StyleRepository: @unchecked Sendable {
    private let db: DatabaseQueue
    init(db: DatabaseQueue) { self.db = db }

    func observeAll() -> AsyncStream<[Style]> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { db in
                try Style.order(Style.Columns.name).fetchAll(db)
            }
            let cancellable = observation.start(in: db) { error in
                print("StyleRepository observeAll error: \(error)")
            } onChange: { styles in
                continuation.yield(styles)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    func getAll() async throws -> [Style] {
        try await db.read { db in try Style.order(Style.Columns.name).fetchAll(db) }
    }

    func insert(_ style: Style) async throws -> Style {
        try await db.write { db in
            var s = style
            try s.insert(db)
            return s
        }
    }

    func update(_ style: Style) async throws {
        try await db.write { db in
            var s = style
            try s.update(db)
        }
    }

    func delete(_ style: Style) async throws {
        try await db.write { db in try style.delete(db) }
    }
}
