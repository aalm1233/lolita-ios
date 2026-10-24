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
    var stageId: Int64? = nil
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

    func reference(itemId: Int64) async throws -> ItemReferencePrice? {
        try await db.read { @Sendable db in try ItemReferencePrice.fetchOne(db, key: itemId) }
    }

    func getById(_ id: Int64) async throws -> Price? {
        try await db.read { db in try Price.fetchOne(db, key: id) }
    }

    func orderSnapshot(_ id: Int64) async throws -> OrderSnapshot {
        try await db.read { @Sendable db in try OrderRepository.snapshot(db, priceId: id) }
    }

    func insert(_ price: Price) async throws -> Price {
        try await db.write { db in
            let owner = try OrderRepository.orderOwner(db, itemId: price.itemId)
            guard owner.id == price.itemId else { throw ValidationError.invalid("共价小物请在主件订单中记账") }
            var p = try Self.normalized(price)
            try p.insert(db)
            return p
        }
    }

    func update(_ price: Price) async throws {
        let value = try Self.normalized(price)
        try await db.write { db in
            guard try OrderBinding.filter(Column("priceId") == value.id).fetchCount(db) == 0,
                  try PaymentStage.filter(Column("priceId") == value.id).fetchCount(db) == 0,
                  try OrderRefund.filter(Column("priceId") == value.id).fetchCount(db) == 0,
                  try OrderCancellation.fetchOne(db, key: value.id) == nil else {
                throw ValidationError.invalid("请在订单计划中修改当前订单")
            }
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
            guard try OrderBinding.filter(Column("priceId") == price.id).fetchCount(db) == 0,
                  try PaymentStage.filter(Column("priceId") == price.id).fetchCount(db) == 0,
                  try OrderRefund.filter(Column("priceId") == price.id).fetchCount(db) == 0,
                  try OrderCancellation.fetchOne(db, key: price.id) == nil else {
                throw ValidationError.invalid("当前订单不能直接删除，请归档保留原账本")
            }
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
            result.totalPrice = try OrderAccounting.sum([deposit, balance])
        } else if price.type == .full {
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
            let observation = ValueObservation.tracking { @Sendable db in
                try Double.fetchOne(db, sql: """
                    SELECT COALESCE(SUM(pay.amount), 0.0)
                    FROM payments pay JOIN prices p ON pay.priceId = p.id JOIN items i ON p.itemId = i.id
                    WHERE pay.isPaid = 1
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
            let observation = ValueObservation.tracking { @Sendable db in
                try SQLRequest<BrandSpending>(sql: """
                    SELECT b.name AS name, COALESCE(SUM(pay.amount), 0.0) AS totalSpending
                    FROM payments pay
                    INNER JOIN prices p ON pay.priceId = p.id
                    INNER JOIN items i ON p.itemId = i.id
                    INNER JOIN brands b ON i.brandId = b.id
                    WHERE pay.isPaid = 1
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
            let observation = ValueObservation.tracking { @Sendable db in
                try SQLRequest<CategorySpending>(sql: """
                    SELECT c.name AS name, COALESCE(SUM(pay.amount), 0.0) AS totalSpending
                    FROM payments pay
                    INNER JOIN prices p ON pay.priceId = p.id
                    INNER JOIN items i ON p.itemId = i.id
                    INNER JOIN categories c ON i.categoryId = c.id
                    WHERE pay.isPaid = 1
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
            let observation = ValueObservation.tracking { @Sendable db in
                try SQLRequest<StyleSpending>(sql: """
                    SELECT i.style AS style, COALESCE(SUM(pay.amount), 0.0) AS totalSpending
                    FROM payments pay
                    INNER JOIN prices p ON pay.priceId = p.id
                    INNER JOIN items i ON p.itemId = i.id
                    WHERE pay.isPaid = 1 AND i.style IS NOT NULL AND i.style != ''
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
            let observation = ValueObservation.tracking { @Sendable db in
                try SQLRequest<MonthlySpending>(sql: """
                    SELECT strftime('%Y-%m', pay.paidDate / 1000, 'unixepoch', 'localtime') AS yearMonth,
                           COALESCE(SUM(pay.amount), 0.0) AS totalSpending
                    FROM payments pay
                    INNER JOIN prices pr ON pay.priceId = pr.id
                    INNER JOIN items i ON pr.itemId = i.id
                    WHERE pay.isPaid = 1 AND pay.paidDate IS NOT NULL
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
            let observation = ValueObservation.tracking { @Sendable db in
                try SQLRequest<ItemWithSpending>(sql: """
                    SELECT i.name AS itemName, COALESCE(SUM(pay.amount), 0.0) AS totalSpending, i.id AS itemId
                    FROM payments pay
                    INNER JOIN prices p ON pay.priceId = p.id
                    INNER JOIN items i ON p.itemId = i.id
                    WHERE pay.isPaid = 1
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
            let observation = ValueObservation.tracking { @Sendable db in
                try Double.fetchOne(db, sql: """
                    SELECT COALESCE(SUM(COALESCE(r.amount, (SELECT SUM(p.totalPrice) FROM prices p
                      WHERE p.itemId=i.id AND p.purchaseRecordStatus='NEEDS_REVIEW'
                      AND NOT EXISTS(SELECT 1 FROM paymentStages s WHERE s.priceId=p.id)), 0)), 0)
                    FROM items i LEFT JOIN itemReferencePrices r ON r.itemId=i.id WHERE i.status='WISHED'
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
            let observation = ValueObservation.tracking { @Sendable db in
                try SQLRequest<PriorityStats>(sql: """
                    SELECT i.priority AS priority, COUNT(DISTINCT i.id) AS itemCount,
                           COALESCE(SUM(COALESCE(r.amount, (SELECT SUM(p.totalPrice) FROM prices p
                             WHERE p.itemId=i.id AND p.purchaseRecordStatus='NEEDS_REVIEW'
                             AND NOT EXISTS(SELECT 1 FROM paymentStages s WHERE s.priceId=p.id)), 0)), 0) AS totalBudget
                    FROM items i
                    LEFT JOIN itemReferencePrices r ON r.itemId = i.id
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
        try await db.read { @Sendable db in
            let items = try Item.filter(Item.Columns.coordinateId == coordinateId).fetchAll(db)
            let values = OrderAccounting.displayAmounts(prices: try Price.fetchAll(db), bindings: try OrderBinding.fetchAll(db), stages: try PaymentStage.fetchAll(db))
            return try OrderAccounting.sum(items.map { values[$0.id] ?? 0 })
        }
    }

    func getSpendingBySeason() -> AsyncStream<[StyleSpending]> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { @Sendable db in
                try SQLRequest<StyleSpending>(sql: """
                    SELECT i.season AS style, COALESCE(SUM(pay.amount), 0) AS totalSpending
                    FROM payments pay JOIN prices p ON pay.priceId = p.id JOIN items i ON p.itemId = i.id
                    WHERE pay.isPaid = 1 AND i.season IS NOT NULL AND i.season != ''
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
    func saveWithPayments(_ price: Price, initialPaidDate: Int64? = nil, stages: [PaymentStage]? = nil,
                          expected: String? = nil) async throws -> Price {
        let value = try Self.normalized(price)
        return try await db.write { @Sendable db in
            let existing = value.id == 0 ? [] : try PaymentStage.filter(Column("priceId") == value.id).order(Column("id")).fetchAll(db)
            var plan = stages ?? (value.type == .depositBalance
                ? [PaymentStage(name: "定金", amount: value.deposit ?? 0), PaymentStage(name: "尾款", amount: value.balance ?? 0)]
                : [PaymentStage(name: "全款", amount: value.totalPrice)])
            if stages == nil {
                plan = plan.filter { $0.amount > 0 }
                for index in plan.indices where existing.indices.contains(index) {
                    plan[index].id = existing[index].id
                    plan[index].dueDate = existing[index].dueDate
                    plan[index].reminderSet = existing[index].reminderSet
                    plan[index].customReminderDays = existing[index].customReminderDays
                }
            }
            if value.id == 0 { return try OrderRepository.create(db, price: value, stages: plan, initialPaidDate: initialPaidDate) }
            return try OrderRepository.update(db, price: value, stages: plan, expected: expected)
        }
    }
}
