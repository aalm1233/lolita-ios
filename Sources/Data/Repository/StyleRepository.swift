@preconcurrency import GRDB
import Foundation

final class StyleRepository: Sendable {
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
            let old = try Style.fetchOne(db, key: style.id)
            var s = style
            s.name = try InputValidation.name(s.name)
            try s.update(db)
            if let old, old.name != s.name {
                try db.execute(sql: "UPDATE items SET style = ?, updatedAt = ? WHERE style = ?", arguments: [s.name, Int64(Date().timeIntervalSince1970 * 1000), old.name])
            }
        }
    }

    func delete(_ style: Style) async throws {
        try await db.write { db in
            try db.execute(sql: "UPDATE items SET style = NULL, updatedAt = ? WHERE style = ?", arguments: [Int64(Date().timeIntervalSince1970 * 1000), style.name])
            try style.delete(db)
        }
    }
}
