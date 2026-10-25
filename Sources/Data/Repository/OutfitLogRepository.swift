@preconcurrency import GRDB
import Foundation

final class OutfitLogRepository: Sendable {
    private let db: DatabaseQueue
    init(db: DatabaseQueue) { self.db = db }

    func observeAll() -> AsyncStream<[OutfitLog]> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { @Sendable db in
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
            guard try OutfitLog.fetchOne(db, key: outfitLogId) != nil else { throw ValidationError.invalid("穿搭记录已不存在") }
            try Self.validateNewLinks(in: db, logId: outfitLogId, itemIds: itemIds)
            try OutfitItemCrossRef
                .filter(OutfitItemCrossRef.Columns.outfitLogId == outfitLogId)
                .deleteAll(db)
            for itemId in Set(itemIds) {
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
    private static func validateNewLinks(in db: Database, logId: Int64?, itemIds: [Int64]) throws {
        let historical = try logId.map { id in Set(try OutfitItemCrossRef.filter(OutfitItemCrossRef.Columns.outfitLogId == id).fetchAll(db).map(\.itemId)) } ?? []
        for id in Set(itemIds) {
            guard let item = try Item.fetchOne(db, key: id) else { throw ValidationError.invalid("选中的服饰已删除，请重新选择") }
            guard historical.contains(id) || item.status == .owned else { throw ValidationError.invalid("只能新增已拥有的穿搭服饰，请核对服饰状态") }
        }
    }
    /// A quick record always targets the local day, including its existing item selection.
    func getForDay(containing date: Date, calendar: Calendar = .current) async throws -> (log: OutfitLog, itemIds: [Int64])? {
        let range = try Self.dayRange(containing: date, calendar: calendar)
        return try await db.read { @Sendable db in
            guard let log = try Self.dayLog(in: db, start: range.start, end: range.end) else { return nil }
            let itemIds = try OutfitItemCrossRef
                .filter(OutfitItemCrossRef.Columns.outfitLogId == log.id)
                .fetchAll(db)
                .map(\.itemId)
            return (log, itemIds)
        }
    }

    /// Check for an existing day again inside the write transaction. Two quick
    /// editors opened before either saves must not create two records.
    func saveForDay(containing date: Date, calendar: Calendar = .current,
                    preferredLogId: Int64? = nil, note: String,
                    imageUrls: [String], itemIds: [Int64]) async throws -> OutfitLog {
        guard !itemIds.isEmpty else { throw ValidationError.invalid("请至少选择一件服饰") }
        let range = try Self.dayRange(containing: date, calendar: calendar)
        let now = Int64(date.timeIntervalSince1970 * 1000)
        let result = try await db.write { @Sendable db -> (OutfitLog, [String]) in
            var existing: OutfitLog?
            if let preferredLogId, let preferred = try OutfitLog.fetchOne(db, key: preferredLogId),
               preferred.date >= range.start, preferred.date < range.end {
                existing = preferred
            } else {
                existing = try Self.dayLog(in: db, start: range.start, end: range.end)
            }
            try Self.validateNewLinks(in: db, logId: existing?.id, itemIds: itemIds)
            var value = existing ?? OutfitLog(date: range.recordDate, note: "", createdAt: now, updatedAt: now)
            value.date = range.recordDate
            value.note = note
            value.imageUrls = StringList(imageUrls)
            value.updatedAt = now
            if value.id == 0 { try value.insert(db) } else { try value.update(db) }
            try OutfitItemCrossRef.filter(OutfitItemCrossRef.Columns.outfitLogId == value.id).deleteAll(db)
            for itemId in Set(itemIds) {
                try OutfitItemCrossRef(outfitLogId: value.id, itemId: itemId).insert(db)
            }
            let removedImages = Set(existing?.imageUrls.values ?? []).subtracting(imageUrls)
            return (value, Array(removedImages))
        }
        if !result.1.isEmpty { try? ImageFileHelper.deleteUnreferenced(paths: result.1, db: db) }
        return result.0
    }

    private static func dayLog(in db: Database, start: Int64, end: Int64) throws -> OutfitLog? {
        try OutfitLog
            .filter(OutfitLog.Columns.date >= start && OutfitLog.Columns.date < end)
            .order(OutfitLog.Columns.date.desc, OutfitLog.Columns.id.desc)
            .fetchOne(db)
    }

    private static func dayRange(containing date: Date, calendar: Calendar) throws -> (start: Int64, end: Int64, recordDate: Int64) {
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start),
              let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: start) else {
            throw ValidationError.invalid("无法确定今天的日期，请检查系统时间")
        }
        return (Int64(start.timeIntervalSince1970 * 1000),
                Int64(end.timeIntervalSince1970 * 1000),
                Int64(noon.timeIntervalSince1970 * 1000))
    }

    func save(_ log: OutfitLog, itemIds: [Int64]) async throws -> OutfitLog {
        try await db.write { db in
            try Self.validateNewLinks(in: db, logId: log.id > 0 ? log.id : nil, itemIds: itemIds)
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
