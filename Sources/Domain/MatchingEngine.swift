import Foundation

struct ItemVector {
    let itemId: Int64
    let vector: [Double]
}

struct MatchScore {
    let item: Item
    let score: Double
}

final class MatchingEngine {
    static let styles = ["甜系", "古典", "哥特", "田园", "中华", "其他"]
    static let colors = [
        "白色", "黑色", "粉色", "红色", "蓝色", "紫色",
        "绿色", "黄色", "棕色", "米色", "灰色", "酒红",
        "藏蓝", "薄荷", "奶茶", "多色"
    ]
    static let seasons = ["春", "夏", "秋", "冬", "四季"]

    func encode(_ item: Item) -> ItemVector {
        let styleVec = Self.styles.map { item.style == $0 ? 1.0 : 0.0 }
        let colorVec = Self.colors.map { item.colors.values.contains($0) ? 1.0 : 0.0 }
        let seasonVec = Self.seasons.map { s in
            item.season?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.contains(s) == true ? 1.0 : 0.0
        }
        return ItemVector(itemId: item.id, vector: styleVec + colorVec + seasonVec)
    }

    func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count else { return 0.0 }
        let dot = zip(a, b).reduce(0.0) { $0 + $1.0 * $1.1 }
        let normA = sqrt(a.reduce(0.0) { $0 + $1 * $1 })
        let normB = sqrt(b.reduce(0.0) { $0 + $1 * $1 })
        guard normA != 0 && normB != 0 else { return 0.0 }
        return dot / (normA * normB)
    }

    func recommend(
        target: Item,
        candidates: [Item],
        coOccurringItemIds: Set<Int64>,
        historyBoost: Double = 1.3,
        topN: Int = 5
    ) -> [MatchScore] {
        let targetVec = encode(target)
        return candidates.compactMap { candidate in
            let candidateVec = encode(candidate)
            var score = cosineSimilarity(targetVec.vector, candidateVec.vector)
            if coOccurringItemIds.contains(candidate.id) {
                score *= historyBoost
            }
            guard score > 0.0 else { return nil }
            return MatchScore(item: candidate, score: score)
        }
        .sorted { $0.score > $1.score }
        .prefix(topN)
        .map { $0 }
    }
}
