import Foundation
@preconcurrency import GRDB

enum StorageTree {
    static func validate(_ nodes: [StorageNode], rooms: Set<Int64>) throws {
        guard Set(nodes.map(\.id)).count == nodes.count, nodes.allSatisfy({ $0.id > 0 }) else { throw ValidationError.invalid("收纳位置标识重复或无效") }
        let byId = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        var siblings = Set<String>()
        for node in nodes {
            let name = node.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard rooms.contains(node.locationId), !name.isEmpty, name.count <= 120 else { throw ValidationError.invalid("请选择有效房间，收纳名称需为 1 至 120 个字") }
            guard siblings.insert("\(node.locationId):\(node.parentNodeId ?? 0):\(name.lowercased())").inserted else { throw ValidationError.invalid("同一位置下已有同名收纳位置") }
            var current = node; var visited = Set<Int64>()
            while true {
                guard visited.insert(current.id).inserted, visited.count <= 2 else { throw ValidationError.invalid("不能循环收纳，最多支持房间、柜架、层格三级") }
                guard let parentId = current.parentNodeId else { break }
                guard let parent = byId[parentId], parent.locationId == node.locationId else { throw ValidationError.invalid("上级位置不属于所选房间") }
                current = parent
            }
        }
    }
    static func descendants(_ id: Int64, nodes: [StorageNode]) -> Set<Int64> {
        guard nodes.contains(where: { $0.id == id }) else { return [] }
        var result: Set<Int64> = [id]
        while true {
            let next = result.union(nodes.filter { $0.parentNodeId.map(result.contains) ?? false }.map(\.id))
            if next == result { return result }; result = next
        }
    }
    static func path(roomId: Int64?, nodeId: Int64?, rooms: [Location], nodes: [StorageNode]) -> String {
        guard let roomId, let room = rooms.first(where: { $0.id == roomId }) else { return "未设置位置" }
        var labels = [String](); var id = nodeId; var seen = Set<Int64>()
        while let currentId = id {
            guard seen.insert(currentId).inserted, seen.count <= 2,
                  let node = nodes.first(where: { $0.id == currentId }), node.locationId == roomId else { return room.name + " → 位置待核对" }
            labels.insert(node.name, at: 0); id = node.parentNodeId
        }
        return ([room.name] + labels).joined(separator: " → ")
    }
}

final class StorageRepository: Sendable {
    private let db: DatabaseQueue
    init(db: DatabaseQueue) { self.db = db }
    func getAll() async throws -> [StorageNode] { try await db.read { try StorageNode.order(Column("sortOrder"), Column("id")).fetchAll($0) } }
    func save(_ node: StorageNode) async throws -> StorageNode {
        let result = try await db.write { db -> (StorageNode, [String]) in
            var value = node; value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let graph = try StorageNode.fetchAll(db)
            if value.id > 0 {
                guard let old = graph.first(where: { $0.id == value.id }), old.locationId == value.locationId, old.parentNodeId == value.parentNodeId else { throw ValidationError.invalid("位置已移动或删除，请重新打开") }
                value.createdAt = old.createdAt
            }
            var candidate = value; if candidate.id == 0 { candidate.id = Int64.max }
            try StorageTree.validate(graph.filter { $0.id != value.id } + [candidate], rooms: Set(Location.fetchAll(db).map(\.id)))
            value.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
            if value.id == 0 { try value.insert(db) } else { try value.update(db) }
            return (value, graph.first(where: { $0.id == value.id })?.imageUrl.map { [$0] } ?? [])
        }
        try? ImageFileHelper.deleteUnreferenced(paths: result.1, db: db)
        return result.0
    }
    func move(nodeId: Int64, roomId: Int64, parentId: Int64?) async throws {
        try await db.write { db in
            let graph = try StorageNode.fetchAll(db)
            let ids = StorageTree.descendants(nodeId, nodes: graph)
            guard !ids.isEmpty, parentId.map({ !ids.contains($0) }) ?? true else { throw ValidationError.invalid("不能移动到自身或下级位置") }
            let changed = graph.map { node -> StorageNode in
                var value = node
                if ids.contains(node.id) { value.locationId = roomId; if node.id == nodeId { value.parentNodeId = parentId } }
                return value
            }
            try StorageTree.validate(changed, rooms: Set(Location.fetchAll(db).map(\.id)))
            for node in changed where ids.contains(node.id) { try node.update(db) }
            for var item in try Item.fetchAll(db) where item.storageNodeId.map(ids.contains) == true {
                item.locationId = roomId; try item.update(db)
            }
            try Self.rewriteDrafts(db) { item in if item.storageNodeId.map(ids.contains) == true { item.locationId = roomId } }
        }
    }
    func delete(nodeId: Int64, clearContents: Bool = false) async throws {
        let images = try await db.write { db -> [String] in
            let graph = try StorageNode.fetchAll(db), ids = StorageTree.descendants(nodeId, nodes: try StorageNode.fetchAll(db))
            guard !ids.isEmpty else { throw ValidationError.invalid("位置已删除") }
            let items = try Item.fetchAll(db).filter { $0.storageNodeId.map(ids.contains) == true }
            guard clearContents || (ids.count == 1 && items.isEmpty) else { throw ValidationError.invalid("位置包含子位置或物品，请先移动，或明确清空位置") }
            for var item in items { item.storageNodeId = nil; item.locationId = nil; try item.update(db) }
            try Self.rewriteDrafts(db) { item in if item.storageNodeId.map(ids.contains) == true { item.storageNodeId = nil } }
            let removed = graph.filter { ids.contains($0.id) }.sorted { ($0.parentNodeId == nil ? 0 : 1) > ($1.parentNodeId == nil ? 0 : 1) }
            for node in removed { try node.delete(db) }
            return removed.compactMap(\.imageUrl)
        }
        try? ImageFileHelper.deleteUnreferenced(paths: images, db: db)
    }
    func deleteRoom(_ room: Location, clearContents: Bool = false) async throws {
        let images = try await db.write { db -> [String] in
            let nodes = try StorageNode.filter(Column("locationId") == room.id).fetchAll(db)
            let items = try Item.filter(Column("locationId") == room.id).fetchAll(db)
            guard clearContents || (nodes.isEmpty && items.isEmpty) else { throw ValidationError.invalid("房间仍有收纳位置或物品，请先移动内容") }
            for var item in items { item.storageNodeId = nil; item.locationId = nil; try item.update(db) }
            try Self.rewriteDrafts(db) { item in if item.locationId == room.id { item.storageNodeId = nil; item.locationId = nil } }
            for node in nodes.sorted(by: { ($0.parentNodeId == nil ? 0 : 1) > ($1.parentNodeId == nil ? 0 : 1) }) { try node.delete(db) }
            try room.delete(db)
            return nodes.compactMap(\.imageUrl) + [room.imageUrl].compactMap { $0 }
        }
        try? ImageFileHelper.deleteUnreferenced(paths: images, db: db)
    }
    func setMembership(nodeId: Int64, originalIds: Set<Int64>, selectedIds: Set<Int64>) async throws {
        try await db.write { db in
            guard let node = try StorageNode.fetchOne(db, key: nodeId) else { throw ValidationError.invalid("收纳位置已删除") }
            for id in selectedIds.subtracting(originalIds) {
                guard var item = try Item.fetchOne(db, key: id), try Self.isOwned(db, item: item) else { throw ValidationError.invalid("仅已拥有物品可以收纳，请刷新后重试") }
                item.locationId = node.locationId; item.storageNodeId = node.id; try item.update(db)
            }
            for id in originalIds.subtracting(selectedIds) {
                if var item = try Item.fetchOne(db, key: id), item.storageNodeId == node.id {
                    item.storageNodeId = nil; item.locationId = nil; try item.update(db)
                }
            }
        }
    }
    func placeImported(ids: Set<Int64>, roomId: Int64?, nodeId: Int64?) async throws {
        try await db.write { db in
            for id in ids {
                guard var item = try Item.fetchOne(db, key: id), try Self.isOwned(db, item: item) else { throw ValidationError.invalid("仅已拥有物品可安排收纳，请重新读取") }
                let previous = item; item.locationId = roomId; item.storageNodeId = nodeId
                try Self.validatePlacement(db, item: item, previous: previous); try item.update(db)
            }
            for draft in try ItemDraft.fetchAll(db) where draft.targetItemId.map(ids.contains) == true {
                var item = try draft.item(); item.locationId = roomId; item.storageNodeId = nodeId
                var next = try ItemDraft.make(id: draft.id, item: item, baseline: draft.baselineUpdatedAt)
                next.updatedAt = draft.updatedAt; try next.update(db)
            }
        }
    }

    static func isOwned(_ db: Database, item: Item) throws -> Bool {
        guard item.status == .owned else { return false }
        if item.includedInParentPrice, let parent = item.parentItemId { return try Item.fetchOne(db, key: parent)?.status == .owned }
        return true
    }
    static func validatePlacement(_ db: Database, item: Item, previous: Item?) throws {
        guard item.storageNodeId == nil || item.locationId != nil else { throw ValidationError.invalid("请先选择房间") }
        if let room = item.locationId { guard try Location.fetchOne(db, key: room) != nil else { throw ValidationError.invalid("房间已删除") } }
        if let node = item.storageNodeId { guard try StorageNode.fetchOne(db, key: node)?.locationId == item.locationId else { throw ValidationError.invalid("收纳位置不属于所选房间") } }
        if item.locationId != nil, try !isOwned(db, item: item) {
            guard let previous, previous.locationId == item.locationId, previous.storageNodeId == item.storageNodeId else { throw ValidationError.invalid("仅已拥有物品可以设置收纳位置") }
        }
        _ = try WardrobeSpecifications.decode(item.specificationsJson)
    }
    private static func rewriteDrafts(_ db: Database, change: (inout Item) -> Void) throws {
        for draft in try ItemDraft.fetchAll(db) {
            var item = try draft.item(); change(&item)
            let updated = try ItemDraft.make(id: draft.id, item: item, baseline: draft.baselineUpdatedAt)
            var saved = updated; saved.updatedAt = draft.updatedAt; try saved.update(db)
        }
    }
}
