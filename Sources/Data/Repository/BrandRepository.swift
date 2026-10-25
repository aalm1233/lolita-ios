@preconcurrency import GRDB
import Foundation

final class BrandRepository: Sendable {
    private let db: DatabaseQueue
    init(db: DatabaseQueue) { self.db = db }

    func observeAll() -> AsyncStream<[Brand]> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { db in
                try Brand.order(Brand.Columns.name).fetchAll(db)
            }
            let cancellable = observation.start(in: db) { error in
                print("BrandRepository observeAll error: \(error)")
            } onChange: { brands in
                continuation.yield(brands)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    func getAll() async throws -> [Brand] {
        try await db.read { db in try Brand.order(Brand.Columns.name).fetchAll(db) }
    }

    func insert(_ brand: Brand) async throws -> Brand {
        let prepared = try BuiltInLibrary.prepareNewBrand(brand)
        do {
            return try await db.write { db in
                var b = prepared
                try b.insert(db)
                return b
            }
        } catch {
            if prepared.logoUrl != brand.logoUrl, let path = prepared.logoUrl {
                try? ImageFileHelper.deleteUnreferenced(paths: [path], db: db)
            }
            throw error
        }
    }

    func update(_ brand: Brand) async throws {
        try await db.write { db in
            let b = brand
            try b.update(db)
        }
    }

    func delete(_ brand: Brand) async throws {
        _ = try await db.write { db in try brand.delete(db) }
    }
}
