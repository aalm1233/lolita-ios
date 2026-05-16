import GRDB
import Foundation

struct Coordinate: Codable, FetchableRecord, PersistableRecord {
    var id: Int64 = 0
    var name: String
    var description: String
    var imageUrls: StringList = StringList()
    var createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    var updatedAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)

    static let databaseTableName = "coordinates"

    enum Columns: String, ColumnExpression {
        case id, name, description, imageUrls, createdAt, updatedAt
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
