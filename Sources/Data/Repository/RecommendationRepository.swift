@preconcurrency import GRDB
import Foundation

// MatchScore and MatchingEngine defined in Domain/MatchingEngine.swift

final class RecommendationRepository: Sendable {
    private let db: DatabaseQueue
    init(db: DatabaseQueue) { self.db = db }

    func getRecommendations(for item: Item, topN: Int = 5) async throws -> [MatchScore] {
        let outfitRepo = OutfitLogRepository(db: db)
        let outfitIds = try await outfitRepo.getCoOccurringItemIds(for: item.id)
        let (candidates, coordinateIds) = try await db.read { @Sendable db in
            let categories = try Category.fetchAll(db)
            let groups = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.group) })
            let targetGroup = groups[item.categoryId]
            let owned = try Item
                .filter(Item.Columns.id != item.id)
                .filter(Item.Columns.status == ItemStatus.owned)
                .fetchAll(db)
            let filtered = owned.filter { candidate in
                targetGroup == nil || groups[candidate.categoryId] != targetGroup
            }
            let coordinateIds: Set<Int64>
            if let coordinateId = item.coordinateId {
                coordinateIds = Set(try Item.filter(Item.Columns.coordinateId == coordinateId && Item.Columns.id != item.id).fetchAll(db).map(\.id))
            } else { coordinateIds = [] }
            return (filtered, coordinateIds)
        }
        let engine = MatchingEngine()
        return engine.recommend(target: item, candidates: candidates, coOccurringItemIds: outfitIds.union(coordinateIds), topN: topN)
    }
}
