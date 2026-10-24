@preconcurrency import GRDB
import Foundation

final class AfterSaleRepository: Sendable {
    private let db: DatabaseQueue
    init(db: DatabaseQueue) { self.db = db }

    func reference(itemId: Int64) async throws -> ItemReferencePrice? {
        try await db.read { @Sendable db in try ItemReferencePrice.fetchOne(db, key: itemId) }
    }
    func saveReference(itemId: Int64, amount: Double, note: String, expected: ItemReferencePrice?) async throws {
        try OrderAccounting.validate(amount)
        let note = try Self.note(note)
        try await db.write { @Sendable db in
            guard let item = try Item.fetchOne(db, key: itemId), !item.includedInParentPrice else {
                throw ValidationError.invalid("物品不存在，或请到共价主件记录参考价")
            }
            let old = try ItemReferencePrice.fetchOne(db, key: itemId)
            guard old == expected else { throw ValidationError.invalid("参考价已变化，请返回重新核对") }
            try ItemReferencePrice(itemId: itemId, amount: amount, note: note, revision: try Self.nextRevision(old?.revision)).save(db)
        }
    }
    func removeReference(itemId: Int64, expected: ItemReferencePrice) async throws {
        try await db.write { @Sendable db in
            guard try ItemReferencePrice.fetchOne(db, key: itemId) == expected else { throw ValidationError.invalid("参考价已变化，请返回重新核对") }
            try db.execute(sql: "DELETE FROM itemReferencePrices WHERE itemId = ?", arguments: [itemId])
        }
    }
    static func nextRevision(_ old: Int64?) throws -> Int64 {
        let (next, overflow) = (old ?? 0).addingReportingOverflow(1)
        guard !overflow, (old ?? 0) >= 0 else { throw ValidationError.invalid("记录版本异常，请核对原备份") }
        return next
    }
    static func note(_ text: String) throws -> String {
        guard text.count <= 500 else { throw ValidationError.invalid("备注最多 500 字") }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func check(_ order: OrderSnapshot, expected: String) throws {
        guard !expected.isEmpty, order.fingerprint == expected else { throw ValidationError.invalid("账目或物品已变化，请返回重新核对") }
    }
    func recordRefund(_ value: OrderRefund, expected: String) async throws -> OrderRefund {
        try await db.write { @Sendable db in
            var value = value; value.note = try Self.note(value.note)
            guard !value.operationId.isEmpty, value.operationId.count <= 100 else { throw ValidationError.invalid("退款操作标识无效") }
            if let old = try OrderRefund.filter(Column("operationId") == value.operationId).fetchOne(db) {
                guard old.priceId == value.priceId, old.amount == value.amount, old.kind == value.kind,
                      old.receivedAt == value.receivedAt, old.note == value.note else { throw ValidationError.invalid("这次退款保存已完成，内容已变化，请重新核对") }
                return old
            }
            let order = try OrderRepository.snapshot(db, priceId: value.priceId)
            try Self.check(order, expected: expected)
            try OrderAccounting.validate(value.amount, positive: true)
            guard value.receivedAt > 0, value.receivedAt <= Int64(Date().timeIntervalSince1970 * 1000) else {
                throw ValidationError.invalid("请填写已经发生的真实到账日期")
            }
            guard try OrderAccounting.cents(value.amount) <= OrderAccounting.cents(order.netAmount) else {
                throw ValidationError.invalid("退款超过尚未退回的原实付")
            }
            value.id = 0; value.voidedAt = nil; try value.insert(db)
            return value
        }
    }
    func voidRefund(_ id: Int64, expected: String) async throws {
        try await db.write { @Sendable db in
            guard var old = try OrderRefund.fetchOne(db, key: id) else { throw ValidationError.invalid("退款记录已不存在") }
            let order = try OrderRepository.snapshot(db, priceId: old.priceId)
            try Self.check(order, expected: expected)
            guard old.voidedAt == nil else { throw ValidationError.invalid("退款已撤销") }
            old.voidedAt = Int64(Date().timeIntervalSince1970 * 1000); try old.update(db)
        }
    }
    func cancelOrder(priceId: Int64, expectedRefund: Double?, note: String, expected: String, confirmed: Bool) async throws {
        guard confirmed else { throw ValidationError.invalid("请明确确认取消整笔订单及共价小物回到心愿") }
        if let expectedRefund { try OrderAccounting.validate(expectedRefund) }
        let note = try Self.note(note)
        try await db.write { @Sendable db in
            let order = try OrderRepository.snapshot(db, priceId: priceId)
            try Self.check(order, expected: expected)
            if let amount = expectedRefund {
                guard try OrderAccounting.cents(amount) >= OrderAccounting.cents(order.refundedAmount),
                      try OrderAccounting.cents(amount) <= OrderAccounting.cents(order.paidAmount) else {
                    throw ValidationError.invalid("约定退款总额须介于已退回金额和原实付之间")
                }
            }
            if var old = order.cancellation {
                old.expectedRefundTotal = expectedRefund; old.note = note; old.revision = try Self.nextRevision(old.revision); try old.update(db)
            } else {
                guard order.isTracked else { throw ValidationError.invalid("仅资料已核对的当前订单可取消") }
                try OrderCancellation(priceId: priceId, expectedRefundTotal: expectedRefund, note: note).insert(db)
                try db.execute(sql: "DELETE FROM orderBindings WHERE priceId = ?", arguments: [priceId])
                try db.execute(sql: "UPDATE items SET status = 'WISHED' WHERE id = ? OR (parentItemId = ? AND includedInParentPrice = 1)", arguments: [order.price.itemId, order.price.itemId])
            }
        }
    }
    static func requireRefundCoverage(_ order: OrderSnapshot, paid: Double) throws {
        guard try OrderAccounting.cents(paid) >= OrderAccounting.cents(order.refundedAmount) else {
            throw ValidationError.invalid("更正后的实付不能低于已退回金额，请先核对退款记录")
        }
    }
}
