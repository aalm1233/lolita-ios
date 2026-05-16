import GRDB
import Foundation

struct Brand: Codable, FetchableRecord, PersistableRecord {
    var id: Int64 = 0
    var name: String
    var isPreset: Bool = false
    var logoUrl: String? = nil
    var createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)

    static let databaseTableName = "brands"

    enum Columns: String, ColumnExpression {
        case id, name, isPreset, logoUrl, createdAt
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
