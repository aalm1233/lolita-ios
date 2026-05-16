import GRDB
import Foundation

struct Category: Codable, FetchableRecord, PersistableRecord {
    var id: Int64 = 0
    var name: String
    var group: CategoryGroup = .clothing
    var isPreset: Bool = false
    var createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)

    static let databaseTableName = "categories"

    enum Columns: String, ColumnExpression {
        case id, name, group, isPreset, createdAt
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
