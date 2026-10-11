@preconcurrency import GRDB
import Foundation

// MARK: - DTOs for JOIN queries

struct BrandSpending: Codable, FetchableRecord {
    var name: String
    var totalSpending: Double
}

struct CategorySpending: Codable, FetchableRecord {
    var name: String
    var totalSpending: Double
}

struct StyleSpending: Codable, FetchableRecord {
    var style: String
    var totalSpending: Double
}

struct MonthlySpending: Codable, FetchableRecord {
    var yearMonth: String
    var totalSpending: Double
}

struct ItemWithSpending: Codable, FetchableRecord {
    var itemName: String
    var totalSpending: Double
    var itemId: Int64
}

struct PriorityStats: Codable, FetchableRecord {
    var priority: String
    var itemCount: Int
    var totalBudget: Double
}

struct PaymentWithItemInfo: Codable, FetchableRecord {
    var paymentId: Int64
    var amount: Double
    var dueDate: Int64
    var isPaid: Bool
    var paidDate: Int64?
    var priceId: Int64
    var priceType: String
    var itemName: String
    var itemId: Int64
}

final class PriceRepository: Sendable {
    private let db: DatabaseQueue
    init(db: DatabaseQueue) { self.db = db }

    // MARK: - CRUD

    func getByItem(_ itemId: Int64) async throws -> [Price] {
        try await db.read { db in
            try Price
                .filter(Price.Columns.itemId == itemId)
                .order(Price.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    func getById(_ id: Int64) async throws -> Price? {
        try await db.read { db in try Price.fetchOne(db, key: id) }
    }

    func insert(_ price: Price) async throws -> Price {
        try await db.write { db in
            var p = try Self.normalized(price)
            try p.insert(db)
            return p
        }
    }

    func update(_ price: Price) async throws {
        let value = try Self.normalized(price)
        try await db.write { db in
            let old = try Price.fetchOne(db, key: value.id)
            try value.update(db)
            try ItemRepository.refreshPaymentStatus(db, itemId: value.itemId)
            if let old, old.itemId != value.itemId {
                try ItemRepository.refreshPaymentStatus(db, itemId: old.itemId)
            }
        }
    }

    func delete(_ price: Price) async throws {
        try await db.write { db in
            try price.delete(db)
            try ItemRepository.refreshPaymentStatus(db, itemId: price.itemId)
        }
    }

    private static func normalized(_ price: Price) throws -> Price {
        var result = price
        if price.type == .depositBalance {
            let deposit = price.deposit ?? 0
            let balance = price.balance ?? 0
            guard deposit.isFinite, balance.isFinite, deposit >= 0, balance >= 0 else {
                throw ValidationError.invalid("定金和尾款必须是有效的非负金额")
            }
            result.totalPrice = deposit + balance
        } else {
            result.deposit = nil
            result.balance = nil
        }
        guard result.totalPrice.isFinite, result.totalPrice >= 0 else {
            throw ValidationError.invalid("总价无效")
        }
        return result
    }

    // MARK: - Spending queries

    func getTotalSpending() -> AsyncStream<Double> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { db in
                try Double.fetchOne(db, sql: """
                    SELECT COALESCE(SUM(p.totalPrice), 0.0)
                    FROM prices p INNER JOIN items i ON p.itemId = i.id
                    WHERE i.status = 'OWNED'
                """) ?? 0.0
            }
            let cancellable = observation.start(in: db) { error in
                print("PriceRepository getTotalSpending error: \(error)")
            } onChange: { val in
                continuation.yield(val)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    func getSpendingByBrand() -> AsyncStream<[BrandSpending]> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { db in
                try SQLRequest<BrandSpending>(sql: """
                    SELECT b.name AS name, COALESCE(SUM(p.totalPrice), 0.0) AS totalSpending
                    FROM prices p
                    INNER JOIN items i ON p.itemId = i.id
                    INNER JOIN brands b ON i.brandId = b.id
                    WHERE i.status = 'OWNED'
                    GROUP BY b.name
                    ORDER BY totalSpending DESC
                """).fetchAll(db)
            }
            let cancellable = observation.start(in: db) { error in
                print("PriceRepository getSpendingByBrand error: \(error)")
            } onChange: { val in
                continuation.yield(val)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    func getSpendingByCategory() -> AsyncStream<[CategorySpending]> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { db in
                try SQLRequest<CategorySpending>(sql: """
                    SELECT c.name AS name, COALESCE(SUM(p.totalPrice), 0.0) AS totalSpending
                    FROM prices p
                    INNER JOIN items i ON p.itemId = i.id
                    INNER JOIN categories c ON i.categoryId = c.id
                    WHERE i.status = 'OWNED'
                    GROUP BY c.name
                    ORDER BY totalSpending DESC
                """).fetchAll(db)
            }
            let cancellable = observation.start(in: db) { error in
                print("PriceRepository getSpendingByCategory error: \(error)")
            } onChange: { val in
                continuation.yield(val)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    func getSpendingByStyle() -> AsyncStream<[StyleSpending]> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { db in
                try SQLRequest<StyleSpending>(sql: """
                    SELECT i.style AS style, COALESCE(SUM(p.totalPrice), 0.0) AS totalSpending
                    FROM prices p
                    INNER JOIN items i ON p.itemId = i.id
                    WHERE i.status = 'OWNED' AND i.style IS NOT NULL AND i.style != ''
                    GROUP BY i.style
                    ORDER BY totalSpending DESC
                """).fetchAll(db)
            }
            let cancellable = observation.start(in: db) { error in
                print("PriceRepository getSpendingByStyle error: \(error)")
            } onChange: { val in
                continuation.yield(val)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    func getMonthlySpending() -> AsyncStream<[MonthlySpending]> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { db in
                try SQLRequest<MonthlySpending>(sql: """
                    SELECT strftime('%Y-%m', pay.dueDate / 1000, 'unixepoch') AS yearMonth,
                           COALESCE(SUM(pay.amount), 0.0) AS totalSpending
                    FROM payments pay
                    INNER JOIN prices pr ON pay.priceId = pr.id
                    INNER JOIN items i ON pr.itemId = i.id
                    WHERE i.status IN ('OWNED', 'PENDING_BALANCE')
                      AND pay.isPaid = 1
                    GROUP BY yearMonth
                    ORDER BY yearMonth ASC
                """).fetchAll(db)
            }
            let cancellable = observation.start(in: db) { error in
                print("PriceRepository getMonthlySpending error: \(error)")
            } onChange: { val in
                continuation.yield(val)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    func getMostExpensiveItem() -> AsyncStream<ItemWithSpending?> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { db in
                try SQLRequest<ItemWithSpending>(sql: """
                    SELECT i.name AS itemName, COALESCE(SUM(p.totalPrice), 0.0) AS totalSpending, i.id AS itemId
                    FROM prices p
                    INNER JOIN items i ON p.itemId = i.id
                    WHERE i.status = 'OWNED'
                    GROUP BY i.id
                    ORDER BY totalSpending DESC
                    LIMIT 1
                """).fetchOne(db)
            }
            let cancellable = observation.start(in: db) { error in
                print("PriceRepository getMostExpensiveItem error: \(error)")
            } onChange: { val in
                continuation.yield(val)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    func getWishlistTotalBudget() -> AsyncStream<Double> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { db in
                try Double.fetchOne(db, sql: """
                    SELECT COALESCE(SUM(p.totalPrice), 0.0)
                    FROM prices p INNER JOIN items i ON p.itemId = i.id
                    WHERE i.status = 'WISHED'
                """) ?? 0.0
            }
            let cancellable = observation.start(in: db) { error in
                print("PriceRepository getWishlistTotalBudget error: \(error)")
            } onChange: { val in
                continuation.yield(val)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    func getWishlistByPriorityStats() -> AsyncStream<[PriorityStats]> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { db in
                try SQLRequest<PriorityStats>(sql: """
                    SELECT i.priority AS priority, COUNT(DISTINCT i.id) AS itemCount,
                           COALESCE(SUM(p.totalPrice), 0.0) AS totalBudget
                    FROM items i
                    LEFT JOIN prices p ON p.itemId = i.id
                    WHERE i.status = 'WISHED'
                    GROUP BY i.priority
                """).fetchAll(db)
            }
            let cancellable = observation.start(in: db) { error in
                print("PriceRepository getWishlistByPriorityStats error: \(error)")
            } onChange: { val in
                continuation.yield(val)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }
}

extension PriceRepository {
    func getTotalByCoordinate(_ coordinateId: Int64) async throws -> Double {
        try await db.read { db in
            try Double.fetchOne(db, sql: "SELECT COALESCE(SUM(p.totalPrice), 0) FROM prices p JOIN items i ON p.itemId = i.id WHERE i.coordinateId = ?", arguments: [coordinateId]) ?? 0
        }
    }

    func getSpendingBySeason() -> AsyncStream<[StyleSpending]> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { db in
                try SQLRequest<StyleSpending>(sql: """
                    SELECT i.season AS style, COALESCE(SUM(p.totalPrice), 0) AS totalSpending
                    FROM prices p JOIN items i ON p.itemId = i.id
                    WHERE i.status = 'OWNED' AND i.season IS NOT NULL AND i.season != ''
                    GROUP BY i.season ORDER BY totalSpending DESC
                    """).fetchAll(db)
            }
            let token = observation.start(in: db, onError: { _ in continuation.finish() }, onChange: { continuation.yield($0) })
            continuation.onTermination = { _ in token.cancel() }
        }
    }
}

extension PriceRepository {
    /// Create the initial payment schedule, or rebuild only unpaid amounts on price edits.
    /// Paid history is retained and deducted, so editing cannot charge an amount twice.
    func saveWithPayments(_ price: Price, initialPaidDate: Int64? = nil) async throws -> Price {
        let value = try Self.normalized(price)
        return try await db.write { db in
            var saved = value
            let original = value.id == 0 ? nil : try Price.fetchOne(db, key: value.id)
            if value.id != 0 && original == nil { throw ValidationError.invalid("价格记录已不存在") }
            let oldPayments = try Payment.filter(Payment.Columns.priceId == value.id).fetchAll(db)
            let paid = oldPayments.filter(\.isPaid).reduce(0) { $0 + $1.amount }
            guard saved.totalPrice + 0.001 >= paid else { throw ValidationError.invalid("总价不能低于已付款金额，请先核对付款记录") }
            if saved.id == 0 { try saved.insert(db) } else { try saved.update(db) }
            let changed = original == nil || original?.type != saved.type || original?.totalPrice != saved.totalPrice
                || original?.deposit != saved.deposit || original?.balance != saved.balance
            if changed {
                try Payment.filter(Payment.Columns.priceId == saved.id && Payment.Columns.isPaid == false).deleteAll(db)
                let now = Int64(Date().timeIntervalSince1970 * 1000)
                func add(amount: Double, paidDate: Int64?) throws {
                    guard amount > 0 else { return }
                    var payment = Payment(priceId: saved.id, amount: amount, dueDate: paidDate ?? now,
                                          isPaid: paidDate != nil, paidDate: paidDate)
                    try payment.insert(db)
                }
                let date = original == nil ? initialPaidDate : nil
                if saved.type == .full {
                    try add(amount: max(0, saved.totalPrice - paid), paidDate: date)
                } else {
                    let deposit = saved.deposit ?? 0
                    let balance = saved.balance ?? 0
                    try add(amount: max(0, deposit - paid), paidDate: date)
                    try add(amount: max(0, balance - max(0, paid - deposit)), paidDate: nil)
                }
            }
            try ItemRepository.refreshPaymentStatus(db, itemId: saved.itemId)
            return saved
        }
    }
}
