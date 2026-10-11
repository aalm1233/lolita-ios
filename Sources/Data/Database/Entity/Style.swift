import GRDB
import Foundation

struct Style: Codable, Sendable, FetchableRecord, MutablePersistableRecord {
    var id: Int64 = 0
    var name: String
    var isPreset: Bool = false
    var createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)

    static let databaseTableName = "styles"

    enum Columns: String, ColumnExpression {
        case id, name, isPreset, createdAt
    }

    // Room treats 0 as an unset ID; SQLite/GRDB needs NULL to generate one.
    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id == 0 ? nil : id
        container["name"] = name
        container["isPreset"] = isPreset
        container["createdAt"] = createdAt
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
