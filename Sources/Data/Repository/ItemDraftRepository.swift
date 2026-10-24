import Foundation
@preconcurrency import GRDB

final class ItemDraftRepository: Sendable {
    private let db: DatabaseQueue
    init(db: DatabaseQueue) { self.db = db }
    func get(_ id: String) async throws -> ItemDraft? { try await db.read { try ItemDraft.fetchOne($0, key: id) } }
    func save(_ draft: ItemDraft) async throws {
        _ = try draft.item()
        guard !draft.id.isEmpty, draft.id.count <= 100, draft.allImagePaths.allSatisfy({ !$0.isEmpty }) else { throw ValidationError.invalid("草稿信息无效") }
        let previous = try await db.write { db -> [String] in
            if let target = draft.targetItemId, try Item.fetchOne(db, key: target) == nil { throw ValidationError.invalid("原物品已删除，无法保存编辑草稿") }
            let paths = try ItemDraft.fetchOne(db, key: draft.id)?.allImagePaths ?? []
            try draft.save(db)
            return paths
        }
        try? ImageFileHelper.deleteUnreferenced(paths: previous, db: db)
    }
    func delete(_ id: String) async throws {
        let paths = try await db.write { db -> [String] in
            let paths = try ItemDraft.fetchOne(db, key: id)?.allImagePaths ?? []
            try ItemDraft.deleteOne(db, key: id)
            return paths
        }
        try? ImageFileHelper.deleteUnreferenced(paths: paths, db: db)
    }
}
