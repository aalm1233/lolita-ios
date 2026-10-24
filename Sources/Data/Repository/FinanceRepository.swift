@preconcurrency import GRDB
import Foundation

struct FinanceEntry: Sendable, Identifiable {
    var id: String
    var itemName: String
    var priceId: Int64
    var amount: Double
    var date: Int64?
    var isPaid: Bool
    var isRefund = false
}
struct FinanceMonth: Sendable {
    var budget: MonthlyBudget?
    var paid: Double
    var refunded: Double
    var pending: Double
    var earlierPending: Double
    var undatedPending: Double
    var undatedPaid: Double
    var entries: [FinanceEntry]
    var undated: [FinanceEntry]
    var net: Double { (try? OrderAccounting.sum([paid, -refunded])) ?? 0 }
    var projectedRemaining: Double? { budget.flatMap { try? OrderAccounting.sum([Double($0.amountCents) / 100, -net, -pending, -earlierPending]) } }
}
struct FinanceSnapshot: Sendable {
    var entries: [FinanceEntry] = []
    var budgets: [MonthlyBudget] = []
    var totalPaid: Double { (try? OrderAccounting.sum(entries.filter { $0.isPaid && !$0.isRefund }.map(\.amount))) ?? 0 }
    var totalRefunded: Double { (try? OrderAccounting.sum(entries.filter(\.isRefund).map { -$0.amount })) ?? 0 }
    var totalNet: Double { (try? OrderAccounting.sum([totalPaid, -totalRefunded])) ?? 0 }
    static func monthKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year!, c.month!)
    }
    func month(_ date: Date, calendar: Calendar = .current) -> FinanceMonth {
        let range = PaymentMonthRange(month: date, calendar: calendar)
        let dated = entries.filter { $0.date.map { $0 >= range.start && $0 < range.end } ?? false }
        let earlier = entries.filter { !$0.isPaid && ($0.date.map { $0 < range.start } ?? false) }
        func sum(_ rows: [FinanceEntry]) -> Double { (try? OrderAccounting.sum(rows.map(\.amount))) ?? 0 }
        return FinanceMonth(budget: budgets.first { $0.month == Self.monthKey(date, calendar: calendar) },
            paid: sum(dated.filter { $0.isPaid && !$0.isRefund }), refunded: abs(sum(dated.filter(\.isRefund))),
            pending: sum(dated.filter { !$0.isPaid }), earlierPending: sum(earlier),
            undatedPending: sum(entries.filter { !$0.isPaid && $0.date == nil }),
            undatedPaid: sum(entries.filter { $0.isPaid && $0.date == nil }),
            entries: (dated + earlier).sorted { ($0.date ?? 0, $0.id) < ($1.date ?? 0, $1.id) },
            undated: entries.filter { $0.date == nil })
    }
}

final class FinanceRepository: Sendable {
    private let db: DatabaseQueue
    init(db: DatabaseQueue) { self.db = db }
    static func snapshot(_ db: Database) throws -> FinanceSnapshot {
        let items = Dictionary(uniqueKeysWithValues: try Item.fetchAll(db).map { ($0.id, $0) })
        let prices = try Price.fetchAll(db)
        let priceMap = Dictionary(uniqueKeysWithValues: prices.map { ($0.id, $0) })
        var entries: [FinanceEntry] = []
        for payment in try Payment.filter(Payment.Columns.isPaid == true).fetchAll(db) {
            guard let price = priceMap[payment.priceId], let item = items[price.itemId] else { continue }
            entries.append(FinanceEntry(id: "payment-\(payment.id)", itemName: item.name, priceId: price.id,
                                        amount: payment.amount, date: payment.paidDate, isPaid: true))
        }
        for refund in try OrderRefund.filter(Column("voidedAt") == nil).fetchAll(db) {
            guard let price = priceMap[refund.priceId], let item = items[price.itemId] else { continue }
            entries.append(FinanceEntry(id: "refund-\(refund.id)", itemName: item.name, priceId: price.id,
                                        amount: -refund.amount, date: refund.receivedAt, isPaid: true, isRefund: true))
        }
        for binding in try OrderBinding.fetchAll(db) {
            let order = try OrderRepository.snapshot(db, priceId: binding.priceId)
            guard order.isTracked, items[binding.itemId]?.status != .wished else { continue }
            for stage in order.stages {
                guard let amount = order.stageRemaining[stage.id], amount > 0 else { continue }
                entries.append(FinanceEntry(id: "stage-\(stage.id)", itemName: items[binding.itemId]?.name ?? "物品", priceId: order.id,
                                            amount: amount, date: stage.dueDate, isPaid: false))
            }
        }
        return FinanceSnapshot(entries: entries, budgets: try MonthlyBudget.order(Column("month")).fetchAll(db))
    }
    func get() async throws -> FinanceSnapshot { try await db.read { @Sendable db in try Self.snapshot(db) } }
    func observe() -> AsyncStream<FinanceSnapshot> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { @Sendable db in try Self.snapshot(db) }
            let token = observation.start(in: db, onError: { _ in continuation.finish() }, onChange: { continuation.yield($0) })
            continuation.onTermination = { _ in token.cancel() }
        }
    }
    static func validateMonth(_ month: String) throws {
        let components = month.split(separator: "-", omittingEmptySubsequences: false)
        guard month.count == 7, components.count == 2, components[0].count == 4, components[1].count == 2,
              let year = Int(components[0]), let number = Int(components[1]), (1...9999).contains(year), (1...12).contains(number) else {
            throw ValidationError.invalid("月份格式无效")
        }
    }
    func saveBudget(month: String, amount: Double, expected: MonthlyBudget?) async throws {
        try Self.validateMonth(month); try OrderAccounting.validate(amount)
        let cents = try OrderAccounting.cents(amount)
        try await db.write { @Sendable db in
            let old = try MonthlyBudget.fetchOne(db, key: month)
            guard old == expected else { throw ValidationError.invalid("预算已变化，请返回重新核对") }
            try MonthlyBudget(month: month, amountCents: cents, revision: try AfterSaleRepository.nextRevision(old?.revision)).save(db)
        }
    }
    func deleteBudget(_ expected: MonthlyBudget) async throws {
        try await db.write { @Sendable db in
            guard try MonthlyBudget.fetchOne(db, key: expected.month) == expected else { throw ValidationError.invalid("预算已变化，请重新核对") }
            try expected.delete(db)
        }
    }
}
