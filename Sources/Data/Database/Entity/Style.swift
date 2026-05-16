import GRDB
import Foundation

struct Style: Codable, FetchableRecord, PersistableRecord {
    var id: Int64 = 0
    var name: String
    var isPreset: Bool = false
    var createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)

    static let databaseTableName = "styles"

    enum Columns: String, ColumnExpression {
        case id, name, isPreset, createdAt
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
