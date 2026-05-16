import GRDB
import Foundation

struct OutfitLog: Codable, FetchableRecord, PersistableRecord {
    var id: Int64 = 0
    var date: Int64
    var note: String
    var imageUrls: StringList = StringList()
    var createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    var updatedAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)

    static let databaseTableName = "outfitLogs"

    enum Columns: String, ColumnExpression {
        case id, date, note, imageUrls, createdAt, updatedAt
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
