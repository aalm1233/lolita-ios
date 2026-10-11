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
        try await db.read { db in try Payment.fetchOne(db, key: id) }
    }

    func insert(_ payment: Payment) async throws -> Payment {
        try await db.write { db in
            guard payment.amount.isFinite, payment.amount >= 0 else {
                throw ValidationError.invalid("付款金额无效")
            }
            try Self.validateReminderDays(payment.customReminderDays)
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
            try payment.delete(db)
            if let price { try ItemRepository.refreshPaymentStatus(db, itemId: price.itemId) }
        }
    }

    func markPaid(_ paymentId: Int64, at date: Date = Date()) async throws {
        let timestamp = Int64(date.timeIntervalSince1970 * 1000)
        try await db.write { @Sendable db in
            guard var payment = try Payment.fetchOne(db, key: paymentId) else {
                throw ValidationError.invalid("付款记录已被删除")
            }
            guard !payment.isPaid else { return }
            payment.isPaid = true
            payment.paidDate = timestamp
            try payment.update(db)
            if let price = try Price.fetchOne(db, key: payment.priceId) {
                try ItemRepository.refreshPaymentStatus(db, itemId: price.itemId)
            }
        }
    }

    private static func validateReminderDays(_ days: Int?) throws {
        if let days, !(0...365).contains(days) {
            throw ValidationError.invalid("提前天数请输入 0 到 365 的整数")
        }
    }

    private static func reminderRecords(_ db: Database) throws -> [PaymentReminderRecord] {
        try SQLRequest<PaymentReminderRecord>(sql: """
            SELECT pay.id AS paymentId, pay.amount, pay.dueDate, pay.isPaid,
                   pay.reminderSet, pay.customReminderDays, pay.createdAt, i.name AS itemName
            FROM payments pay
            INNER JOIN prices pr ON pay.priceId = pr.id
            INNER JOIN items i ON pr.itemId = i.id
            WHERE i.status IN ('OWNED', 'PENDING_BALANCE')
            ORDER BY pay.dueDate, pay.id
            """).fetchAll(db)
    }

    func getReminderRecords() async throws -> [PaymentReminderRecord] {
        try await db.read { @Sendable db in try Self.reminderRecords(db) }
    }

    func observeReminderRecords() -> AsyncStream<[PaymentReminderRecord]> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { @Sendable db in try Self.reminderRecords(db) }
            let token = observation.start(in: db, onError: { _ in continuation.finish() },
                                          onChange: { continuation.yield($0) })
            continuation.onTermination = { _ in token.cancel() }
        }
    }

    // MARK: - Calendar queries

    func getByDateRange(start: Int64, end: Int64) -> AsyncStream<[PaymentWithItemInfo]> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { @Sendable db in
                try SQLRequest<PaymentWithItemInfo>(sql: """
                    SELECT pay.id AS paymentId, pay.amount, pay.dueDate AS dueDate,
                           pay.isPaid AS isPaid, pay.paidDate AS paidDate,
                           pr.id AS priceId, pr.type AS priceType,
                           i.name AS itemName, i.id AS itemId
                    FROM payments pay
                    INNER JOIN prices pr ON pay.priceId = pr.id
                    INNER JOIN items i ON pr.itemId = i.id
                    WHERE pay.dueDate >= ? AND pay.dueDate < ?
                      AND i.status IN ('OWNED', 'PENDING_BALANCE')
                    ORDER BY pay.dueDate ASC
                """, arguments: [start, end]).fetchAll(db)
            }
            let cancellable = observation.start(in: db) { error in
                print("PaymentRepository getByDateRange error: \(error)")
            } onChange: { val in
                continuation.yield(val)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    func getTotalUnpaidAmount() -> AsyncStream<Double> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { @Sendable db in
                try Double.fetchOne(db, sql: """
                    SELECT COALESCE(SUM(p.amount), 0.0) FROM payments p
                    INNER JOIN prices pr ON p.priceId = pr.id
                    INNER JOIN items i ON pr.itemId = i.id
                    WHERE p.isPaid = 0 AND i.status IN ('OWNED', 'PENDING_BALANCE')
                """) ?? 0.0
            }
            let cancellable = observation.start(in: db) { error in
                print("PaymentRepository getTotalUnpaidAmount error: \(error)")
            } onChange: { val in
                continuation.yield(val)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    func getOverdueAmount() -> AsyncStream<Double> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { @Sendable db in
                try Double.fetchOne(db, sql: """
                    SELECT COALESCE(SUM(p.amount), 0.0) FROM payments p
                    INNER JOIN prices pr ON p.priceId = pr.id
                    INNER JOIN items i ON pr.itemId = i.id
                    WHERE p.isPaid = 0 AND p.dueDate < ?
                      AND i.status IN ('OWNED', 'PENDING_BALANCE')
                """, arguments: [Int64(Date().timeIntervalSince1970 * 1000)]) ?? 0.0
            }
            let cancellable = observation.start(in: db) { error in
                print("PaymentRepository getOverdueAmount error: \(error)")
            } onChange: { val in
                continuation.yield(val)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }
}
