@preconcurrency import GRDB
import Foundation

final class CategoryRepository: @unchecked Sendable {
    private let db: DatabaseQueue
    init(db: DatabaseQueue) { self.db = db }

    func observeAll() -> AsyncStream<[Category]> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { db in
                try Category.order(Category.Columns.group, Category.Columns.name).fetchAll(db)
            }
            let cancellable = observation.start(in: db) { error in
                print("CategoryRepository observeAll error: \(error)")
            } onChange: { categories in
                continuation.yield(categories)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    func getAll() async throws -> [Category] {
        try await db.read { db in try Category.order(Category.Columns.group, Category.Columns.name).fetchAll(db) }
    }

    func insert(_ category: Category) async throws -> Category {
        try await db.write { db in
            var c = category
            try c.insert(db)
            return c
        }
    }

    func update(_ category: Category) async throws {
        try await db.write { db in
            var c = category
            try c.update(db)
        }
    }

    func delete(_ category: Category) async throws {
        try await db.write { db in try category.delete(db) }
    }
}
