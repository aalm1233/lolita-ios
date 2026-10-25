@preconcurrency import GRDB
import Foundation

struct PurchaseReview: Identifiable, Sendable {
    let item: Item
    let orderItemId: Int64
    let priceId: Int64?
    let recordStatus: PurchaseRecordStatus?
    let unknownPaymentDate: Bool
    var id: Int64 { item.id }
    var reason: String {
        var reasons: [String] = []
        if priceId == nil { reasons.append("当前订单未设置，价格与付款资料待补") }
        else if recordStatus == .historicalOwned { reasons.append("已确认拥有，付款资料待核对") }
        else if recordStatus != .tracked { reasons.append("购买状态与付款资料待核对") }
        if unknownPaymentDate { reasons.append("实付日期待补") }
        return reasons.joined(separator: "；")
    }
}

final class PurchaseReviewRepository: Sendable {
    private let db: DatabaseQueue
    init(db: DatabaseQueue) { self.db = db }
    func observe() -> AsyncStream<[PurchaseReview]> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { @Sendable db in try Self.fetch(db) }
            let token = observation.start(in: db, onError: { _ in continuation.finish() }, onChange: { continuation.yield($0) })
            continuation.onTermination = { _ in token.cancel() }
        }
    }
    func getAll() async throws -> [PurchaseReview] { try await db.read { @Sendable db in try Self.fetch(db) } }
    private static func fetch(_ db: Database) throws -> [PurchaseReview] {
        let items = try Item.fetchAll(db)
        let catalog = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let bindings = Dictionary(uniqueKeysWithValues: try OrderBinding.fetchAll(db).map { ($0.itemId, $0) })
        let unknown = Set(try Payment.filter(Payment.Columns.isPaid == true && Payment.Columns.paidDate == nil).fetchAll(db).map(\.priceId))
        return items.compactMap { item -> PurchaseReview? in
            let ownerId = item.includedInParentPrice ? item.parentItemId ?? item.id : item.id
            guard let owner = catalog[ownerId] else { return nil }
            let binding = bindings[ownerId]
            let unknownDate = binding.map { unknown.contains($0.priceId) } ?? false
            guard item.status == .pendingReview || binding.map({ $0.purchaseRecordStatus != .tracked }) == true || (binding == nil && owner.status != .wished) || unknownDate else { return nil }
            return PurchaseReview(item: item, orderItemId: ownerId, priceId: binding?.priceId, recordStatus: binding?.purchaseRecordStatus, unknownPaymentDate: unknownDate)
        }.sorted { $0.item.updatedAt == $1.item.updatedAt ? $0.id > $1.id : $0.item.updatedAt > $1.item.updatedAt }
    }
}
