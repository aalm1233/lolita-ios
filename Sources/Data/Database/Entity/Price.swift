@preconcurrency import GRDB
import Foundation

struct Price: Codable, Sendable, FetchableRecord, MutablePersistableRecord {
    var id: Int64 = 0
    var itemId: Int64
    var type: PriceType
    var totalPrice: Double
    var deposit: Double? = nil
    var balance: Double? = nil
    var createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    var shipping: Double = 0
    var purchaseRecordStatus: PurchaseRecordStatus = .needsReview

    static let databaseTableName = "prices"

    enum Columns: String, ColumnExpression {
        case id, itemId, type, totalPrice, deposit, balance, createdAt, shipping, purchaseRecordStatus
    }

    // Room treats 0 as an unset ID; SQLite/GRDB needs NULL to generate one.
    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id == 0 ? nil : id
        container["itemId"] = itemId
        container["type"] = type
        container["totalPrice"] = totalPrice
        container["deposit"] = deposit
        container["balance"] = balance
        container["createdAt"] = createdAt
        container["shipping"] = shipping
        container["purchaseRecordStatus"] = purchaseRecordStatus
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    static let item = belongsTo(Item.self)

    var item: QueryInterfaceRequest<Item> {
        request(for: Price.item)
    }
}
