@preconcurrency import GRDB
import Foundation

final class PaymentRepository: Sendable {
    private let db: DatabaseQueue
    init(db: DatabaseQueue) { self.db = db }

    // MARK: - CRUD

    func getByPrice(_ priceId: Int64) -> AsyncStream<[Payment]> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { @Sendable db in
                try Payment
                    .filter(Payment.Columns.priceId == priceId)
                    .order(Payment.Columns.dueDate.asc)
                    .fetchAll(db)
            }
            let cancellable = observation.start(in: db) { error in
                print("PaymentRepository getByPrice error: \(error)")
            } onChange: { payments in
                continuation.yield(payments)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    func getById(_ id: Int64) async throws -> Payment? {
        try await db.read { @Sendable db in
            guard id != Int64.min else { return nil }
            if id < 0 {
                guard let stage = try PaymentStage.fetchOne(db, key: -id) else { return nil }
                let snapshot = try OrderRepository.snapshot(db, priceId: stage.priceId)
                guard snapshot.isTracked, let remaining = snapshot.stageRemaining[stage.id], remaining > 0 else { return nil }
                return Payment(id: id, priceId: stage.priceId, amount: remaining, dueDate: stage.dueDate ?? 0,
                               reminderSet: stage.reminderSet, customReminderDays: stage.customReminderDays, stageId: stage.id)
            }
            return try Payment.fetchOne(db, key: id)
        }
    }

    func orderSnapshot(_ priceId: Int64) async throws -> OrderSnapshot {
        try await db.read { @Sendable db in try OrderRepository.snapshot(db, priceId: priceId) }
    }

    func saveActual(_ payment: Payment, expected: String?) async throws -> Payment {
        try await db.write { @Sendable db in
            if payment.id == 0 {
                return try OrderRepository.recordPayment(db, priceId: payment.priceId, amount: payment.amount,
                    paidDate: payment.paidDate, stageId: payment.stageId, operationId: payment.operationId ?? UUID().uuidString, expected: expected)
            }
            try OrderRepository.editPayment(db, payment: payment, expected: expected)
            return try Payment.fetchOne(db, key: payment.id)!
        }
    }

    func insert(_ payment: Payment) async throws -> Payment {
        try await db.write { db in
            guard payment.amount.isFinite, payment.amount >= 0 else {
                throw ValidationError.invalid("付款金额无效")
            }
            try Self.validateReminderDays(payment.customReminderDays)
            if try OrderBinding.filter(Column("priceId") == payment.priceId).fetchCount(db) > 0 {
                guard payment.isPaid else { throw ValidationError.invalid("应付计划请在付款阶段中设置") }
                return try OrderRepository.recordPayment(db, priceId: payment.priceId, amount: payment.amount,
                    paidDate: payment.paidDate, stageId: payment.stageId, operationId: payment.operationId ?? UUID().uuidString)
            }
            try Self.requireLegacyWritable(db, priceId: payment.priceId)
            var p = payment
            try p.insert(db)
            if let price = try Price.fetchOne(db, key: p.priceId) {
                try ItemRepository.refreshPaymentStatus(db, itemId: price.itemId)
            }
            return p
        }
    }

    func update(_ payment: Payment) async throws {
        try await db.write { db in
            guard payment.amount.isFinite, payment.amount >= 0 else {
                throw ValidationError.invalid("付款金额无效")
            }
            try Self.validateReminderDays(payment.customReminderDays)
            let old = try Payment.fetchOne(db, key: payment.id)
            guard old != nil else { throw ValidationError.invalid("付款记录已被删除") }
            guard old?.priceId == payment.priceId else { throw ValidationError.invalid("不能更换付款所属订单") }
            if try OrderBinding.filter(Column("priceId") == payment.priceId).fetchCount(db) > 0 {
                try OrderRepository.editPayment(db, payment: payment)
                return
            }
            try Self.requireLegacyWritable(db, priceId: payment.priceId)
            try payment.update(db)
            for priceId in Set([payment.priceId, old?.priceId].compactMap { $0 }) {
                if let price = try Price.fetchOne(db, key: priceId) {
                    try ItemRepository.refreshPaymentStatus(db, itemId: price.itemId)
                }
            }
        }
    }

    func delete(_ payment: Payment) async throws {
        try await db.write { db in
            let price = try Price.fetchOne(db, key: payment.priceId)
            if try OrderBinding.filter(Column("priceId") == payment.priceId).fetchCount(db) > 0 {
                _ = try OrderRepository.active(db, priceId: payment.priceId)
                guard payment.isPaid else { throw ValidationError.invalid("不能删除历史计划") }
            } else { try Self.requireLegacyWritable(db, priceId: payment.priceId) }
            try AfterSaleRepository.requireRefundCoverage(try OrderRepository.snapshot(db, priceId: payment.priceId), paid: try OrderAccounting.sum(try Payment.filter(Payment.Columns.priceId == payment.priceId && Payment.Columns.isPaid == true && Payment.Columns.id != payment.id).fetchAll(db).map(\.amount)))
            try payment.delete(db)
            if let price { try ItemRepository.refreshPaymentStatus(db, itemId: price.itemId) }
        }
    }

    func markPaid(_ paymentId: Int64, at date: Date = Date()) async throws {
        let timestamp = Int64(date.timeIntervalSince1970 * 1000)
        try await db.write { @Sendable db in
            guard paymentId != Int64.min else { throw ValidationError.invalid("付款标识无效") }
            if paymentId < 0 {
                guard let stage = try PaymentStage.fetchOne(db, key: -paymentId) else { throw ValidationError.invalid("阶段已被删除") }
                let snapshot = try OrderRepository.active(db, priceId: stage.priceId, trackedOnly: true)
                guard let amount = snapshot.stageRemaining[stage.id], amount > 0 else { return }
                _ = try OrderRepository.recordPayment(db, priceId: stage.priceId, amount: amount, paidDate: timestamp,
                    stageId: stage.id, operationId: "stage-\(stage.id)-\(snapshot.fingerprint)")
                return
            }
            guard var payment = try Payment.fetchOne(db, key: paymentId) else {
                throw ValidationError.invalid("付款记录已被删除")
            }
            guard !payment.isPaid else { return }
            if let stageId = payment.stageId {
                let snapshot = try OrderRepository.active(db, priceId: payment.priceId, trackedOnly: true)
                guard let amount = snapshot.stageRemaining[stageId], amount > 0 else { return }
                _ = try OrderRepository.recordPayment(db, priceId: payment.priceId, amount: amount, paidDate: timestamp,
                    stageId: stageId, operationId: "legacy-plan-\(payment.id)")
                return
            }
            try Self.requireLegacyWritable(db, priceId: payment.priceId)
            payment.isPaid = true
            payment.paidDate = timestamp
            try payment.update(db)
            if let price = try Price.fetchOne(db, key: payment.priceId) {
                try ItemRepository.refreshPaymentStatus(db, itemId: price.itemId)
            }
        }
    }

    private static func requireLegacyWritable(_ db: Database, priceId: Int64) throws {
        guard let price = try Price.fetchOne(db, key: priceId), price.purchaseRecordStatus == .needsReview,
              try PaymentStage.filter(Column("priceId") == priceId).fetchCount(db) == 0,
              try OrderRefund.filter(Column("priceId") == priceId).fetchCount(db) == 0,
              try OrderCancellation.fetchOne(db, key: priceId) == nil else {
            throw ValidationError.invalid("历史账本只供查看，请在当前订单中操作")
        }
    }

    private static func validateReminderDays(_ days: Int?) throws {
        if let days, !(0...365).contains(days) {
            throw ValidationError.invalid("提前天数请输入 0 到 365 的整数")
        }
    }

    /// Calendar/reminders project the remaining plan; archived plans never become debt.
    static func projected(_ db: Database) throws -> [PaymentWithItemInfo] {
        let items = Dictionary(uniqueKeysWithValues: try Item.fetchAll(db).map { ($0.id, $0) })
        let prices = try Price.fetchAll(db)
        let bindings = try OrderBinding.fetchAll(db)
        let active = Set(bindings.map(\.priceId))
        let allStages = try PaymentStage.fetchAll(db)
        let allPayments = try Payment.fetchAll(db)
        var rows: [PaymentWithItemInfo] = []
        for price in prices {
            guard let item = items[price.itemId] else { continue }
            let payments = allPayments.filter { $0.priceId == price.id }
            for payment in payments where payment.isPaid && payment.paidDate != nil {
                rows.append(PaymentWithItemInfo(paymentId: payment.id, amount: payment.amount,
                    dueDate: payment.paidDate!, isPaid: true, paidDate: payment.paidDate, priceId: price.id,
                    priceType: price.type.rawValue, itemName: item.name, itemId: item.id, stageId: payment.stageId))
            }
            let stages = allStages.filter { $0.priceId == price.id }
            if active.contains(price.id) && item.status != .wished {
                let snapshot = OrderSnapshot(price: price, binding: bindings.first { $0.priceId == price.id }, stages: stages, payments: payments)
                for stage in stages where snapshot.isTracked {
                    guard let due = stage.dueDate, let amount = snapshot.stageRemaining[stage.id], amount > 0 else { continue }
                    rows.append(PaymentWithItemInfo(paymentId: -stage.id, amount: amount, dueDate: due, isPaid: false,
                        priceId: price.id, priceType: price.type.rawValue, itemName: item.name, itemId: item.id, stageId: stage.id))
                }
            } else if stages.isEmpty && price.purchaseRecordStatus == .needsReview && item.status != .wished {
                // Compatibility for records inserted through the original repository API.
                for payment in payments where !payment.isPaid {
                    rows.append(PaymentWithItemInfo(paymentId: payment.id, amount: payment.amount, dueDate: payment.dueDate,
                        isPaid: false, priceId: price.id, priceType: price.type.rawValue, itemName: item.name, itemId: item.id))
                }
            }
        }
        return rows.sorted { ($0.dueDate, $0.paymentId) < ($1.dueDate, $1.paymentId) }
    }

    private static func reminderRecords(_ db: Database) throws -> [PaymentReminderRecord] {
        let payments = Dictionary(uniqueKeysWithValues: try Payment.fetchAll(db).map { ($0.id, $0) })
        let stages = Dictionary(uniqueKeysWithValues: try PaymentStage.fetchAll(db).map { ($0.id, $0) })
        return try projected(db).map { row in
            let stage = row.stageId.flatMap { stages[$0] }
            let original = payments[row.paymentId]
            return PaymentReminderRecord(paymentId: row.paymentId, amount: row.amount, dueDate: row.dueDate,
                isPaid: row.isPaid, reminderSet: row.paymentId < 0 ? stage?.reminderSet ?? false : original?.reminderSet ?? false,
                customReminderDays: row.paymentId < 0 ? stage?.customReminderDays : original?.customReminderDays,
                createdAt: original?.createdAt ?? stage?.id ?? 0, itemName: row.itemName)
        }
    }

    func getReminderRecords() async throws -> [PaymentReminderRecord] {
        try await db.read { @Sendable db in try Self.reminderRecords(db) }
    }

    func observeReminderRecords() -> AsyncStream<[PaymentReminderRecord]> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { @Sendable db in try Self.reminderRecords(db) }
            let token = observation.start(in: db, onError: { _ in continuation.finish() }, onChange: { continuation.yield($0) })
            continuation.onTermination = { _ in token.cancel() }
        }
    }

    func getByDateRange(start: Int64, end: Int64) -> AsyncStream<[PaymentWithItemInfo]> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { @Sendable db in
                try Self.projected(db).filter { $0.dueDate >= start && $0.dueDate < end }
            }
            let token = observation.start(in: db, onError: { _ in continuation.finish() }, onChange: { continuation.yield($0) })
            continuation.onTermination = { _ in token.cancel() }
        }
    }

    private func unpaid(before: Int64?) -> AsyncStream<Double> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { @Sendable db in
                if before == nil {
                    let bindings = try OrderBinding.fetchAll(db)
                    let amounts = try bindings.map { binding -> Double in
                        guard try Item.fetchOne(db, key: binding.itemId)?.status != .wished else { return 0 }
                        return try OrderRepository.snapshot(db, priceId: binding.priceId).remainingAmount ?? 0
                    }
                    let legacy = try Self.projected(db).filter { !$0.isPaid && $0.stageId == nil }.map(\.amount)
                    return try OrderAccounting.sum(amounts + legacy)
                }
                let rows = try Self.projected(db).filter { !$0.isPaid && (before == nil || $0.dueDate < before!) }
                return try OrderAccounting.sum(rows.map(\.amount))
            }
            let token = observation.start(in: db, onError: { _ in continuation.finish() }, onChange: { continuation.yield($0) })
            continuation.onTermination = { _ in token.cancel() }
        }
    }
    func getTotalUnpaidAmount() -> AsyncStream<Double> { unpaid(before: nil) }
    func getOverdueAmount() -> AsyncStream<Double> { unpaid(before: Int64(Date().timeIntervalSince1970 * 1000)) }
}
