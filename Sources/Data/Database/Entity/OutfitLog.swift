import GRDB
import Foundation

struct OutfitLog: Codable, Sendable, FetchableRecord, MutablePersistableRecord {
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

    // Room treats 0 as an unset ID; SQLite/GRDB needs NULL to generate one.
    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id == 0 ? nil : id
        container["date"] = date
        container["note"] = note
        container["imageUrls"] = imageUrls
        container["createdAt"] = createdAt
        container["updatedAt"] = updatedAt
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
