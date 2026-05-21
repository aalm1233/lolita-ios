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

final class PriceRepository {
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
            let p = price
            try p.insert(db)
            return p
        }
    }

    func update(_ price: Price) async throws {
        try await db.write { db in try price.update(db) }
    }

    func delete(_ price: Price) async throws {
        try await db.write { db in try price.delete(db) }
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
                    SELECT i.priority AS priority, COUNT(i.id) AS itemCount,
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
