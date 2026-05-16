@preconcurrency import GRDB
import Foundation

// MatchScore and MatchingEngine defined in Domain/MatchingEngine.swift

final class RecommendationRepository {
    private let db: DatabaseQueue
    init(db: DatabaseQueue) { self.db = db }

    func getRecommendations(for item: Item, topN: Int = 5) async throws -> [MatchScore] {
        let outfitRepo = OutfitLogRepository(db: db)
        let coOccurringIds = try await outfitRepo.getCoOccurringItemIds(for: item.id)
        let candidates = try await db.read { db in
            try Item
                .filter(Item.Columns.id != item.id)
                .filter(Item.Columns.status == ItemStatus.owned)
                .fetchAll(db)
        }
        let engine = MatchingEngine()
        return engine.recommend(target: item, candidates: candidates, coOccurringItemIds: coOccurringIds, topN: topN)
    }
}
