import GRDB
import Foundation

struct Coordinate: Codable, Sendable, FetchableRecord, MutablePersistableRecord {
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

    // Room treats 0 as an unset ID; SQLite/GRDB needs NULL to generate one.
    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id == 0 ? nil : id
        container["name"] = name
        container["description"] = description
        container["imageUrls"] = imageUrls
        container["createdAt"] = createdAt
        container["updatedAt"] = updatedAt
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
