@preconcurrency import GRDB
import Foundation

final class SeasonRepository: Sendable {
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
            s.name = try Self.validatedName(s.name)
            try s.insert(db)
            return s
        }
    }

    func update(_ season: Season) async throws {
        try await db.write { db in
            let old = try Season.fetchOne(db, key: season.id)
            var s = season
            s.name = try Self.validatedName(s.name)
            try s.update(db)
            if let old, old.name != s.name {
                try Self.rewriteItemReferences(in: db, oldName: old.name, newName: s.name)
            }
        }
    }

    func delete(_ season: Season) async throws {
        try await db.write { db in
            try Self.rewriteItemReferences(in: db, oldName: season.name, newName: nil)
            try season.delete(db)
        }
    }

    static func validatedName(_ text: String) throws -> String {
        let name = try InputValidation.name(text)
        guard !name.contains(",") else { throw ValidationError.invalid("一个季节名称不能包含逗号，请分别添加") }
        return name
    }

    /// Multi-season values are comma-separated tokens, not a single foreign key.
    static func rewriteItemReferences(in db: Database, oldName: String, newName: String?) throws {
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        for var item in try Item.fetchAll(db) {
            let tokens = item.season?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } ?? []
            guard tokens.contains(oldName) else { continue }
            var seen = Set<String>()
            let updated = tokens.compactMap { $0 == oldName ? newName : $0 }.filter { seen.insert($0).inserted }
            item.season = updated.isEmpty ? nil : updated.joined(separator: ",")
            item.updatedAt = timestamp
            try item.update(db)
        }
    }
}
