@preconcurrency import GRDB
import Foundation

struct ItemReferencePrice: Codable, Sendable, FetchableRecord, PersistableRecord, Equatable {
    var itemId: Int64
    var amount: Double
    var note = ""
    var revision: Int64 = 1
    var updatedAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    static let databaseTableName = "itemReferencePrices"
}

enum RefundKind: String, Codable, CaseIterable, Sendable, DatabaseValueConvertible {
    case refund = "REFUND", priceDifference = "PRICE_DIFFERENCE"
    var title: String { self == .refund ? "退款" : "退差价" }
}

struct OrderRefund: Codable, Sendable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable {
    var id: Int64 = 0
    var priceId: Int64
    var amount: Double
    var kind: RefundKind = .refund
    var receivedAt: Int64
    var note = ""
    var operationId: String
    var createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    var voidedAt: Int64? = nil
    static let databaseTableName = "orderRefunds"
    func encode(to c: inout PersistenceContainer) throws {
        c["id"] = id == 0 ? nil : id; c["priceId"] = priceId; c["amount"] = amount
        c["kind"] = kind; c["receivedAt"] = receivedAt; c["note"] = note
        c["operationId"] = operationId; c["createdAt"] = createdAt; c["voidedAt"] = voidedAt
    }
    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

struct OrderCancellation: Codable, Sendable, FetchableRecord, PersistableRecord, Equatable {
    var priceId: Int64
    var expectedRefundTotal: Double?
    var cancelledAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    var note = ""
    var revision: Int64 = 1
    static let databaseTableName = "orderCancellations"
}

struct MonthlyBudget: Codable, Sendable, FetchableRecord, PersistableRecord, Equatable {
    var month: String
    var amountCents: Int64
    var revision: Int64 = 1
    static let databaseTableName = "monthlyBudgets"
}

enum AfterSaleMigration {
    static func install(_ db: Database) throws {
        try db.create(table: "itemReferencePrices") { t in
            t.column("itemId", .integer).primaryKey().references("items", onDelete: .cascade)
            t.column("amount", .double).notNull(); t.column("note", .text).notNull()
            t.column("revision", .integer).notNull(); t.column("updatedAt", .integer).notNull()
        }
        try db.create(table: "orderRefunds") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("priceId", .integer).notNull().indexed().references("prices", onDelete: .cascade)
            t.column("amount", .double).notNull(); t.column("kind", .text).notNull()
            t.column("receivedAt", .integer).notNull(); t.column("note", .text).notNull()
            t.column("operationId", .text).notNull().unique(); t.column("createdAt", .integer).notNull()
            t.column("voidedAt", .integer)
        }
        try db.create(table: "orderCancellations") { t in
            t.column("priceId", .integer).primaryKey().references("prices", onDelete: .cascade)
            t.column("expectedRefundTotal", .double); t.column("cancelledAt", .integer).notNull()
            t.column("note", .text).notNull(); t.column("revision", .integer).notNull()
        }
        try db.create(table: "monthlyBudgets") { t in
            t.column("month", .text).primaryKey(); t.column("amountCents", .integer).notNull()
            t.column("revision", .integer).notNull()
        }
    }
}
