@preconcurrency import GRDB
import Foundation

final class OutfitLogRepository: Sendable {
    private let db: DatabaseQueue
    init(db: DatabaseQueue) { self.db = db }

    func observeAll() -> AsyncStream<[OutfitLog]> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { db in
                try OutfitLog.order(OutfitLog.Columns.date.desc).fetchAll(db)
            }
            let cancellable = observation.start(in: db) { error in
                print("OutfitLogRepository observeAll error: \(error)")
            } onChange: { logs in
                continuation.yield(logs)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    func getAll() async throws -> [OutfitLog] {
        try await db.read { db in try OutfitLog.order(OutfitLog.Columns.date.desc).fetchAll(db) }
    }

    func getById(_ id: Int64) async throws -> OutfitLog? {
        try await db.read { db in try OutfitLog.fetchOne(db, key: id) }
    }

    func insert(_ outfitLog: OutfitLog) async throws -> OutfitLog {
        try await db.write { db in
            var ol = outfitLog
            try ol.insert(db)
            return ol
        }
    }

    func update(_ outfitLog: OutfitLog) async throws {
        try await db.write { db in
            var ol = outfitLog
            ol.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
            try ol.update(db)
        }
    }

    func delete(_ outfitLog: OutfitLog) async throws {
        try await db.write { db in
            try OutfitItemCrossRef
                .filter(OutfitItemCrossRef.Columns.outfitLogId == outfitLog.id)
                .deleteAll(db)
            try outfitLog.delete(db)
        }
        try? ImageFileHelper.deleteUnreferenced(paths: outfitLog.imageUrls.values, db: db)
    }

    func getItemIds(for outfitLogId: Int64) async throws -> [Int64] {
        try await db.read { db in
            try OutfitItemCrossRef
                .filter(OutfitItemCrossRef.Columns.outfitLogId == outfitLogId)
                .fetchAll(db)
                .map { $0.itemId }
        }
    }

    func setItems(outfitLogId: Int64, itemIds: [Int64]) async throws {
        try await db.write { db in
            try OutfitItemCrossRef
                .filter(OutfitItemCrossRef.Columns.outfitLogId == outfitLogId)
                .deleteAll(db)
            for itemId in itemIds {
                var crossRef = OutfitItemCrossRef(outfitLogId: outfitLogId, itemId: itemId)
                try crossRef.insert(db)
            }
        }
    }

    func getCoOccurringItemIds(for itemId: Int64) async throws -> Set<Int64> {
        try await db.read { db in
            let outfitLogIds = try OutfitItemCrossRef
                .filter(OutfitItemCrossRef.Columns.itemId == itemId)
                .select(OutfitItemCrossRef.Columns.outfitLogId)
                .fetchAll(db)
                .map { $0.outfitLogId }

            let itemIds = try OutfitItemCrossRef
                .filter(outfitLogIds.contains(OutfitItemCrossRef.Columns.outfitLogId))
                .fetchAll(db)
                .map { $0.itemId }

            return Set(itemIds).subtracting([itemId])
        }
    }
}

extension OutfitLogRepository {
    func save(_ log: OutfitLog, itemIds: [Int64]) async throws -> OutfitLog {
        try await db.write { db in
            var value = log
            value.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
            if value.id == 0 { try value.insert(db) } else { try value.update(db) }
            try OutfitItemCrossRef.filter(OutfitItemCrossRef.Columns.outfitLogId == value.id).deleteAll(db)
            for itemId in Set(itemIds) {
                try OutfitItemCrossRef(outfitLogId: value.id, itemId: itemId).insert(db)
            }
            return value
        }
    }
}
