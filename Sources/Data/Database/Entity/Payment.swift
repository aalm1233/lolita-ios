@preconcurrency import GRDB
import Foundation

struct Payment: Codable, FetchableRecord, PersistableRecord {
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

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    static let price = belongsTo(Price.self)

    var price: QueryInterfaceRequest<Price> {
        request(for: Payment.price)
    }
}
