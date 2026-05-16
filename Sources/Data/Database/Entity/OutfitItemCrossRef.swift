import GRDB
import Foundation

struct OutfitItemCrossRef: Codable, FetchableRecord, PersistableRecord {
    var outfitLogId: Int64
    var itemId: Int64

    static let databaseTableName = "outfitItemCrossRef"

    enum Columns: String, ColumnExpression {
        case outfitLogId, itemId
    }
}
