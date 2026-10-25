@preconcurrency import GRDB
import Foundation

final class LookRepository: Sendable {
    private let db: DatabaseQueue
    init(db: DatabaseQueue) { self.db = db }

    func load(itemId: Int64) async throws -> (Item, [LookGroup]) {
        try await db.read { @Sendable db in
            guard let item = try Item.fetchOne(db, key: itemId) else { throw ValidationError.invalid("服饰已不存在") }
            guard item.status == .owned else { throw ValidationError.invalid("请选择已拥有的服饰作为主件") }
            let candidates = try Item.filter(Item.Columns.status == ItemStatus.owned).fetchAll(db)
            let history = Set(try Int64.fetchAll(db, sql: "SELECT itemId FROM outfitItemCrossRef WHERE outfitLogId IN (SELECT outfitLogId FROM outfitItemCrossRef WHERE itemId = ?)", arguments: [itemId]))
            let coordinateIds = item.coordinateId.map { id in Set(candidates.filter { $0.coordinateId == id }.map(\.id)) } ?? []
            return (item, FullLookEngine.build(target: item, candidates: candidates, categories: try Category.fetchAll(db), history: history.union(coordinateIds)))
        }
    }

    /// Validate the reviewed membership inside the same transaction as the new set.
    func save(name: String, reviewed: [Item]) async throws -> Coordinate {
        let name = try InputValidation.name(name)
        guard !reviewed.isEmpty, reviewed.allSatisfy({ $0.id > 0 }), Set(reviewed.map(\.id)).count == reviewed.count else { throw ValidationError.invalid("请选择服饰") }
        return try await db.write { @Sendable db in
            let current = try reviewed.map { expected in
                guard let item = try Item.fetchOne(db, key: expected.id) else { throw ValidationError.invalid("服饰已删除，请刷新搭配后重新选择") }
                guard item.status == .owned else { throw ValidationError.invalid("服饰状态已变化，请刷新搭配后重新选择") }
                guard item.coordinateId == expected.coordinateId else { throw ValidationError.invalid("服饰所属套装已变化，请刷新搭配后重新选择") }
                return item
            }
            var coordinate = Coordinate(name: name, description: "")
            try coordinate.insert(db)
            for (index, item) in current.enumerated() {
                let updatedAt = max(Int64(Date().timeIntervalSince1970 * 1000), item.updatedAt + 1)
                try db.execute(sql: "UPDATE items SET coordinateId = ?, coordinateOrder = ?, updatedAt = ? WHERE id = ?", arguments: [coordinate.id, index, updatedAt, item.id])
            }
            return coordinate
        }
    }
}
