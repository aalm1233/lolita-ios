@preconcurrency import GRDB
import Foundation

/// Selects the current purchase without rewriting historical prices or payments.
struct OrderBinding: Codable, Sendable, FetchableRecord, PersistableRecord, Equatable {
    var itemId: Int64
    var priceId: Int64
    var purchaseRecordStatus: PurchaseRecordStatus = .tracked
    static let databaseTableName = "orderBindings"
}

struct PaymentStage: Codable, Sendable, FetchableRecord, MutablePersistableRecord, Equatable, Identifiable {
    var id: Int64 = 0
    var priceId: Int64 = 0
    var name: String
    var amount: Double
    var dueDate: Int64? = nil
    var reminderSet = false
    var customReminderDays: Int? = nil
    static let databaseTableName = "paymentStages"

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id == 0 ? nil : id
        container["priceId"] = priceId
        container["name"] = name
        container["amount"] = amount
        container["dueDate"] = dueDate
        container["reminderSet"] = reminderSet
        container["customReminderDays"] = customReminderDays
    }

    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
