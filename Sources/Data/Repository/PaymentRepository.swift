@preconcurrency import GRDB
import Foundation

final class PaymentRepository {
    private let db: DatabaseQueue
    init(db: DatabaseQueue) { self.db = db }

    // MARK: - CRUD

    func getByPrice(_ priceId: Int64) -> AsyncStream<[Payment]> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { db in
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
            let p = payment
            try p.insert(db)
            return p
        }
    }

    func update(_ payment: Payment) async throws {
        try await db.write { db in try payment.update(db) }
    }

    func delete(_ payment: Payment) async throws {
        try await db.write { db in try payment.delete(db) }
    }

    // MARK: - Calendar queries

    func getByDateRange(start: Int64, end: Int64) -> AsyncStream<[PaymentWithItemInfo]> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { db in
                try SQLRequest<PaymentWithItemInfo>(sql: """
                    SELECT pay.id AS paymentId, pay.amount, pay.dueDate AS dueDate,
                           pay.isPaid AS isPaid, pay.paidDate AS paidDate,
                           pr.id AS priceId, pr.type AS priceType,
                           i.name AS itemName, i.id AS itemId
                    FROM payments pay
                    INNER JOIN prices pr ON pay.priceId = pr.id
                    INNER JOIN items i ON pr.itemId = i.id
                    WHERE pay.dueDate BETWEEN ? AND ?
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
            let observation = ValueObservation.tracking { db in
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
            let observation = ValueObservation.tracking { db in
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
