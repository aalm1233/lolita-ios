@preconcurrency import GRDB
import Foundation

struct Price: Codable, FetchableRecord, PersistableRecord {
    var id: Int64 = 0
    var itemId: Int64
    var type: PriceType
    var totalPrice: Double
    var deposit: Double? = nil
    var balance: Double? = nil
    var createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)

    static let databaseTableName = "prices"

    enum Columns: String, ColumnExpression {
        case id, itemId, type, totalPrice, deposit, balance, createdAt
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    static let item = belongsTo(Item.self)

    var item: QueryInterfaceRequest<Item> {
        request(for: Price.item)
    }
}
