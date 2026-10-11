@preconcurrency import GRDB
import Foundation

struct Payment: Codable, Sendable, FetchableRecord, MutablePersistableRecord {
    var id: Int64 = 0
    var priceId: Int64
    var amount: Double
    var dueDate: Int64
    var isPaid: Bool = false
    var paidDate: Int64? = nil
    var calendarEventId: Int64? = nil
    var reminderSet: Bool = false
    var customReminderDays: Int? = nil
    var createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)

    static let databaseTableName = "payments"

    enum Columns: String, ColumnExpression {
        case id, priceId, amount, dueDate, isPaid, paidDate
        case calendarEventId, reminderSet, customReminderDays, createdAt
    }

    // Room treats 0 as an unset ID; SQLite/GRDB needs NULL to generate one.
    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id == 0 ? nil : id
        container["priceId"] = priceId
        container["amount"] = amount
        container["dueDate"] = dueDate
        container["isPaid"] = isPaid
        container["paidDate"] = paidDate
        container["calendarEventId"] = calendarEventId
        container["reminderSet"] = reminderSet
        container["customReminderDays"] = customReminderDays
        container["createdAt"] = createdAt
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    static let price = belongsTo(Price.self)

    var price: QueryInterfaceRequest<Price> {
        request(for: Payment.price)
    }
}
