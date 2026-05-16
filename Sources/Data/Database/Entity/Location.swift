import GRDB
import Foundation

struct Location: Codable, FetchableRecord, PersistableRecord {
    var id: Int64 = 0
    var name: String
    var description: String = ""
    var imageUrl: String? = nil
    var sortOrder: Int = 0
    var createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    var updatedAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)

    static let databaseTableName = "locations"

    enum Columns: String, ColumnExpression {
        case id, name, description, imageUrl, sortOrder, createdAt, updatedAt
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
