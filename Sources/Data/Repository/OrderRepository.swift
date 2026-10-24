@preconcurrency import GRDB
import Foundation
import CryptoKit

struct OrderSnapshot: Codable, Sendable, Identifiable {
    var price: Price
    var binding: OrderBinding?
    var stages: [PaymentStage]
    var payments: [Payment]
    var refunds: [OrderRefund] = []
    var cancellation: OrderCancellation? = nil
    var item: Item? = nil
    var sharedItems: [Item] = []
    var refundedAmount: Double { (try? OrderAccounting.sum(refunds.filter { $0.voidedAt == nil }.map(\.amount))) ?? 0 }
    var netAmount: Double { (try? OrderAccounting.sum([paidAmount, -refundedAmount])) ?? 0 }
    var pendingRefund: Double? { cancellation?.expectedRefundTotal.map { max(0, ((try? OrderAccounting.sum([$0, -refundedAmount])) ?? 0)) } }
    var id: Int64 { price.id }
    var isCurrent: Bool { binding?.priceId == price.id && cancellation == nil }
    var isTracked: Bool { isCurrent && binding?.purchaseRecordStatus == .tracked }
    var paidAmount: Double { (try? OrderAccounting.sum(payments.filter(\.isPaid).map(\.amount))) ?? 0 }
    var remainingAmount: Double? {
        guard isTracked else { return nil }
        return max(0, ((try? OrderAccounting.sum([price.totalPrice, -paidAmount])) ?? 0))
    }
    var stageRemaining: [Int64: Double] {
        guard isTracked else { return [:] }
        return (try? OrderAccounting.remainingByStage(stages, payments: payments, total: price.totalPrice)) ?? [:]
    }
    var fingerprint: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(self)).map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() } ?? ""
    }
}

/// All purchase mutations and derived ownership updates share one GRDB write transaction.
final class OrderRepository: Sendable {
    private let db: DatabaseQueue
    init(db: DatabaseQueue) { self.db = db }

    static func snapshot(_ db: Database, priceId: Int64) throws -> OrderSnapshot {
        guard let price = try Price.fetchOne(db, key: priceId) else { throw ValidationError.invalid("订单已被删除") }
        return OrderSnapshot(price: price,
            binding: try OrderBinding.fetchOne(db, key: price.itemId),
            stages: try PaymentStage.filter(Column("priceId") == priceId).order(Column("id")).fetchAll(db),
            payments: try Payment.filter(Payment.Columns.priceId == priceId).order(Payment.Columns.id).fetchAll(db),
            refunds: try OrderRefund.filter(Column("priceId") == priceId).order(Column("id")).fetchAll(db),
            cancellation: try OrderCancellation.fetchOne(db, key: priceId),
            item: try Item.fetchOne(db, key: price.itemId),
            sharedItems: try Item.filter(Column("parentItemId") == price.itemId && Column("includedInParentPrice") == true).order(Column("id")).fetchAll(db))
    }

    func get(_ priceId: Int64) async throws -> OrderSnapshot {
        try await db.read { @Sendable db in try Self.snapshot(db, priceId: priceId) }
    }

    func owner(itemId: Int64) async throws -> Item {
        try await db.read { @Sendable db in try Self.orderOwner(db, itemId: itemId) }
    }

    func observe(itemId: Int64) -> AsyncStream<[OrderSnapshot]> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { @Sendable db in
                let owner = try Self.orderOwner(db, itemId: itemId)
                return try Price.filter(Price.Columns.itemId == owner.id).order(Price.Columns.createdAt.desc, Price.Columns.id.desc)
                    .fetchAll(db).map { try Self.snapshot(db, priceId: $0.id) }
            }
            let token = observation.start(in: db, onError: { _ in continuation.finish() }, onChange: { continuation.yield($0) })
            continuation.onTermination = { _ in token.cancel() }
        }
    }

    static func orderOwner(_ db: Database, itemId: Int64) throws -> Item {
        guard let item = try Item.fetchOne(db, key: itemId) else { throw ValidationError.invalid("物品已被删除") }
        if item.includedInParentPrice, let parent = item.parentItemId {
            guard let owner = try Item.fetchOne(db, key: parent), !owner.includedInParentPrice else {
                throw ValidationError.invalid("共价主件关系无效，请核对资料")
            }
            return owner
        }
        return item
    }

    private static func check(_ snapshot: OrderSnapshot, expected: String?) throws {
        if let expected, snapshot.fingerprint != expected { throw ValidationError.invalid("订单已变化，请刷新后重新核对") }
    }

    static func active(_ db: Database, priceId: Int64, trackedOnly: Bool = false) throws -> OrderSnapshot {
        let snapshot = try snapshot(db, priceId: priceId)
        guard snapshot.isCurrent else { throw ValidationError.invalid("这是历史账本，请先选择当前订单") }
        guard try Item.fetchOne(db, key: snapshot.price.itemId)?.status != .wished else {
            throw ValidationError.invalid("物品已回到心愿，请先核对购买关系")
        }
        guard snapshot.binding?.purchaseRecordStatus != .needsReview else {
            throw ValidationError.invalid("请先核对历史购买与付款资料")
        }
        guard !trackedOnly || snapshot.isTracked else {
            throw ValidationError.invalid("历史已购的计划只供查看，核对实付后才能启用跟踪")
        }
        try OrderAccounting.validate(snapshot.price.totalPrice, positive: true)
        _ = try OrderAccounting.sum(snapshot.payments.filter(\.isPaid).map(\.amount))
        return snapshot
    }

    static func validate(_ price: Price, stages: [PaymentStage]) throws {
        try OrderAccounting.validate(price.totalPrice, positive: true)
        try OrderAccounting.validate(price.shipping)
        guard price.shipping <= price.totalPrice else { throw ValidationError.invalid("邮费不能超过应付总额") }
        if price.type == .depositBalance {
            try OrderAccounting.validate(price.deposit ?? 0)
            try OrderAccounting.validate(price.balance ?? 0)
            guard try OrderAccounting.cents(OrderAccounting.sum([price.deposit ?? 0, price.balance ?? 0])) == OrderAccounting.cents(price.totalPrice) else {
                throw ValidationError.invalid("定金与尾款合计必须等于订单应付总额")
            }
        }
        guard !stages.isEmpty else { throw ValidationError.invalid("请设置至少一个付款阶段") }
        for stage in stages {
            _ = try InputValidation.name(stage.name)
            try OrderAccounting.validate(stage.amount, positive: true)
            if let days = stage.customReminderDays, !(0...365).contains(days) { throw ValidationError.invalid("提醒天数须为 0 至 365") }
            guard !stage.reminderSet || stage.dueDate != nil else { throw ValidationError.invalid("设置提醒前请填写应付日期") }
        }
        guard try OrderAccounting.cents(OrderAccounting.sum(stages.map(\.amount))) == OrderAccounting.cents(price.totalPrice) else {
            throw ValidationError.invalid("各阶段合计必须等于应付总额（含邮费）")
        }
    }

    static func create(_ db: Database, price: Price, stages: [PaymentStage], initialPaidDate: Int64? = nil) throws -> Price {
        try validate(price, stages: stages)
        let item = try orderOwner(db, itemId: price.itemId)
        guard item.id == price.itemId else { throw ValidationError.invalid("小物共用主件订单，请到主件记账") }
        guard try OrderBinding.fetchOne(db, key: item.id) == nil else { throw ValidationError.invalid("已有当前订单，请编辑或先归档") }
        var saved = price; saved.id = 0; saved.purchaseRecordStatus = .tracked
        try saved.insert(db)
        try OrderBinding(itemId: item.id, priceId: saved.id).insert(db)
        var inserted: [PaymentStage] = []
        for var stage in stages {
            stage.id = 0; stage.priceId = saved.id; try stage.insert(db); inserted.append(stage)
        }
        if let date = initialPaidDate, let first = inserted.first {
            var payment = Payment(priceId: saved.id, amount: first.amount, dueDate: date, isPaid: true, paidDate: date,
                                  stageId: first.id, operationId: UUID().uuidString)
            try payment.insert(db)
        }
        // Building a purchase is the explicit action that moves a wish into the ledger.
        try refreshStatuses(db, itemId: item.id, includeWish: true)
        return saved
    }

    func create(price: Price, stages: [PaymentStage], initialPaidDate: Int64? = nil) async throws -> Price {
        try await db.write { @Sendable db in try Self.create(db, price: price, stages: stages, initialPaidDate: initialPaidDate) }
    }

    static func update(_ db: Database, price: Price, stages: [PaymentStage], expected: String? = nil) throws -> Price {
        let old = try active(db, priceId: price.id, trackedOnly: true)
        try check(old, expected: expected); try validate(price, stages: stages)
        guard price.itemId == old.price.itemId else { throw ValidationError.invalid("不能更换订单所属物品") }
        guard try OrderAccounting.cents(price.totalPrice) >= OrderAccounting.cents(old.paidAmount) else {
            throw ValidationError.invalid("订单金额不能低于已付，请核对实付记录")
        }
        let existingIDs = stages.filter { $0.id != 0 }.map(\.id)
        guard Set(existingIDs).count == existingIDs.count else { throw ValidationError.invalid("付款阶段重复") }
        for var stage in stages {
            stage.priceId = price.id
            if stage.id == 0 { try stage.insert(db) }
            else {
                guard old.stages.contains(where: { $0.id == stage.id }) else { throw ValidationError.invalid("阶段不属于当前订单") }
                let paid = try OrderAccounting.sum(old.payments.filter { $0.isPaid && $0.stageId == stage.id }.map(\.amount))
                guard try OrderAccounting.cents(stage.amount) >= OrderAccounting.cents(paid) else { throw ValidationError.invalid("阶段金额不能低于该阶段已付") }
                try stage.update(db)
            }
        }
        for removed in old.stages where !existingIDs.contains(removed.id) {
            // SET NULL detaches allocation only; all original actual amounts and dates stay intact.
            try removed.delete(db)
        }
        var saved = price; saved.createdAt = old.price.createdAt; saved.purchaseRecordStatus = old.price.purchaseRecordStatus
        try saved.update(db)
        try refreshStatuses(db, itemId: saved.itemId)
        return saved
    }

    func update(price: Price, stages: [PaymentStage], expected: String? = nil) async throws -> Price {
        try await db.write { @Sendable db in try Self.update(db, price: price, stages: stages, expected: expected) }
    }

    func bindHistorical(itemId: Int64, priceId: Int64) async throws {
        try await db.write { @Sendable db in
            let owner = try Self.orderOwner(db, itemId: itemId)
            let snapshot = try Self.snapshot(db, priceId: priceId)
            guard snapshot.cancellation == nil else { throw ValidationError.invalid("已取消订单不能重新绑定，请建立新购买") }
            guard owner.id == itemId, snapshot.price.itemId == itemId else { throw ValidationError.invalid("订单不属于这件物品") }
            guard try OrderBinding.fetchOne(db, key: itemId) == nil else { throw ValidationError.invalid("请先归档当前订单") }
            try OrderAccounting.validate(snapshot.price.totalPrice, positive: true)
            try OrderBinding(itemId: itemId, priceId: priceId, purchaseRecordStatus: snapshot.price.purchaseRecordStatus).insert(db)
            try Self.refreshStatuses(db, itemId: itemId)
        }
    }

    func confirmPurchase(priceId: Int64, historicalOwned: Bool, paymentsVerified: Bool = false, expected: String? = nil) async throws {
        try await db.write { @Sendable db in
            var snapshot = try Self.snapshot(db, priceId: priceId)
            try Self.check(snapshot, expected: expected)
            guard snapshot.isCurrent else { throw ValidationError.invalid("请先选择当前订单") }
            guard historicalOwned || paymentsVerified else { throw ValidationError.invalid("请确认真实付款已全部录入，余额与实际一致") }
            if !historicalOwned { try Self.validate(snapshot.price, stages: snapshot.stages) }
            try OrderAccounting.validate(snapshot.price.totalPrice, positive: true)
            for payment in snapshot.payments where payment.isPaid { try OrderAccounting.validate(payment.amount, positive: true) }
            guard snapshot.paidAmount <= snapshot.price.totalPrice else { throw ValidationError.invalid("历史实付超过总额，请先核对原账本") }
            let status: PurchaseRecordStatus = historicalOwned ? .historicalOwned : .tracked
            snapshot.price.purchaseRecordStatus = status; try snapshot.price.update(db)
            try OrderBinding(itemId: snapshot.price.itemId, priceId: priceId, purchaseRecordStatus: status).update(db)
            try Self.refreshStatuses(db, itemId: snapshot.price.itemId, includeWish: true)
        }
    }

    func archive(priceId: Int64, expected: String? = nil) async throws {
        try await db.write { @Sendable db in
            let snapshot = try Self.snapshot(db, priceId: priceId)
            try Self.check(snapshot, expected: expected)
            guard snapshot.isCurrent else { throw ValidationError.invalid("订单已归档") }
            try db.execute(sql: "DELETE FROM orderBindings WHERE priceId = ?", arguments: [priceId])
            // Archiving does not assert ownership, cancel a purchase or invent a payment.
        }
    }

    private static func validateActual(_ snapshot: OrderSnapshot, amount: Double, stageId: Int64?, excluding: Int64? = nil) throws {
        try OrderAccounting.validate(amount, positive: true)
        let others = snapshot.payments.filter { $0.isPaid && $0.id != excluding }
        guard try OrderAccounting.cents(OrderAccounting.sum(others.map(\.amount) + [amount])) <= OrderAccounting.cents(snapshot.price.totalPrice) else {
            throw ValidationError.invalid("付款金额超过订单未付余额")
        }
        if let stageId {
            guard let stage = snapshot.stages.first(where: { $0.id == stageId }) else { throw ValidationError.invalid("付款阶段不属于当前订单") }
            let assigned = try OrderAccounting.sum(others.filter { $0.stageId == stageId }.map(\.amount) + [amount])
            guard try OrderAccounting.cents(assigned) <= OrderAccounting.cents(stage.amount) else { throw ValidationError.invalid("付款超过该阶段金额") }
        }
    }

    static func recordPayment(_ db: Database, priceId: Int64, amount: Double, paidDate: Int64?, stageId: Int64?, operationId: String,
                              expected: String? = nil) throws -> Payment {
        guard !operationId.isEmpty else { throw ValidationError.invalid("付款操作标识无效") }
        if let prior = try Payment.filter(Payment.Columns.operationId == operationId).fetchOne(db) {
            guard prior.priceId == priceId, prior.amount == amount, prior.paidDate == paidDate, prior.stageId == stageId else {
                throw ValidationError.invalid("这次保存已完成，请刷新后核对")
            }
            return prior
        }
        let snapshot = try active(db, priceId: priceId)
        try check(snapshot, expected: expected)
        guard paidDate != nil || snapshot.binding?.purchaseRecordStatus == .historicalOwned else {
            throw ValidationError.invalid("请填写真实付款日期")
        }
        try validateActual(snapshot, amount: amount, stageId: stageId)
        var payment = Payment(priceId: priceId, amount: amount, dueDate: paidDate ?? 0, isPaid: true, paidDate: paidDate,
                              stageId: stageId, operationId: operationId)
        try payment.insert(db); try refreshStatuses(db, itemId: snapshot.price.itemId)
        return payment
    }

    func recordPayment(priceId: Int64, amount: Double, paidDate: Int64?, stageId: Int64? = nil,
                       operationId: String = UUID().uuidString, expected: String? = nil) async throws -> Payment {
        try await db.write { @Sendable db in
            try Self.recordPayment(db, priceId: priceId, amount: amount, paidDate: paidDate, stageId: stageId, operationId: operationId, expected: expected)
        }
    }

    static func editPayment(_ db: Database, payment: Payment, expected: String? = nil) throws {
        let snapshot = try active(db, priceId: payment.priceId)
        try check(snapshot, expected: expected)
        guard let old = snapshot.payments.first(where: { $0.id == payment.id }), old.isPaid, payment.isPaid else {
            throw ValidationError.invalid("只能更正真实付款，计划请在付款阶段中修改")
        }
        guard payment.paidDate != nil || old.paidDate == nil || snapshot.binding?.purchaseRecordStatus == .historicalOwned else {
            throw ValidationError.invalid("请填写真实付款日期")
        }
        try AfterSaleRepository.requireRefundCoverage(snapshot, paid: try OrderAccounting.sum(snapshot.payments.filter { $0.isPaid && $0.id != payment.id }.map(\.amount) + [payment.amount]))
        try validateActual(snapshot, amount: payment.amount, stageId: payment.stageId, excluding: payment.id)
        var saved = payment; saved.createdAt = old.createdAt; saved.operationId = old.operationId
        saved.reminderSet = false; saved.calendarEventId = nil
        try saved.update(db); try refreshStatuses(db, itemId: snapshot.price.itemId)
    }

    func deletePayment(_ id: Int64, expected: String? = nil) async throws {
        try await db.write { @Sendable db in
            guard let payment = try Payment.fetchOne(db, key: id) else { throw ValidationError.invalid("付款已删除") }
            let snapshot = try Self.active(db, priceId: payment.priceId)
            try Self.check(snapshot, expected: expected)
            guard payment.isPaid else { throw ValidationError.invalid("历史计划保留在原账本中，不能当作实付删除") }
            try AfterSaleRepository.requireRefundCoverage(snapshot, paid: try OrderAccounting.sum(snapshot.payments.filter { $0.isPaid && $0.id != id }.map(\.amount)))
            try payment.delete(db); try Self.refreshStatuses(db, itemId: snapshot.price.itemId)
        }
    }

    static func refreshStatuses(_ db: Database, itemId: Int64, includeWish: Bool = false) throws {
        let currentStatus = try Item.fetchOne(db, key: itemId)?.status
        if let binding = try OrderBinding.fetchOne(db, key: itemId),
           includeWish || currentStatus != .wished {
            let snapshot = try snapshot(db, priceId: binding.priceId)
            let status: ItemStatus
            switch binding.purchaseRecordStatus {
            case .historicalOwned: status = .owned
            case .needsReview: status = .pendingReview
            case .tracked:
                status = snapshot.remainingAmount == 0 ? .owned : snapshot.price.type == .depositBalance ? .pendingBalance : .pendingPayment
            }
            try db.execute(sql: "UPDATE items SET status = ? WHERE id = ?", arguments: [status.rawValue, itemId])
        }
        try db.execute(sql: """
            UPDATE items SET status = (SELECT status FROM items parent WHERE parent.id = ?)
            WHERE parentItemId = ? AND includedInParentPrice = 1
            """, arguments: [itemId, itemId])
    }
}
