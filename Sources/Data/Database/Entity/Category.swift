import GRDB
import Foundation

struct Category: Codable, Sendable, FetchableRecord, MutablePersistableRecord {
    var id: Int64 = 0
    var name: String
    var group: CategoryGroup = .clothing
    var isPreset: Bool = false
    var createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)

    static let databaseTableName = "categories"

    enum Columns: String, ColumnExpression {
        case id, name, group, isPreset, createdAt
    }

    // Room treats 0 as an unset ID; SQLite/GRDB needs NULL to generate one.
    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id == 0 ? nil : id
        container["name"] = name
        container["group"] = group
        container["isPreset"] = isPreset
        container["createdAt"] = createdAt
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
