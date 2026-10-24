import Foundation
import GRDB

struct StorageNode: Codable, Sendable, FetchableRecord, MutablePersistableRecord, Identifiable {
    var id: Int64 = 0
    var locationId: Int64
    var parentNodeId: Int64? = nil
    var name: String
    var description = ""
    var imageUrl: String? = nil
    var sortOrder = 0
    var createdAt = Int64(Date().timeIntervalSince1970 * 1000)
    var updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
    static let databaseTableName = "storageNodes"
    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id == 0 ? nil : id
        container["locationId"] = locationId; container["parentNodeId"] = parentNodeId
        container["name"] = name; container["description"] = description; container["imageUrl"] = imageUrl
        container["sortOrder"] = sortOrder; container["createdAt"] = createdAt; container["updatedAt"] = updatedAt
    }
    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

/// Images live outside the JSON payload, so relocation and ZIP restore cover every reference.
struct ItemDraft: Codable, Sendable, FetchableRecord, PersistableRecord, Identifiable {
    var id: String
    var targetItemId: Int64?
    var dataJson: String
    var imagePaths: StringList
    var detailImagePaths: StringList
    var baselineUpdatedAt: Int64?
    var updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
    static let databaseTableName = "itemDrafts"
    var allImagePaths: [String] { imagePaths.values + detailImagePaths.values }
    func item() throws -> Item {
        var item = try JSONDecoder().decode(Item.self, from: Data(dataJson.utf8))
        guard item.id == (targetItemId ?? 0), item.imageUrls.values.isEmpty, item.detailImagePaths.isEmpty else { throw ValidationError.invalid("草稿标识或图片引用无效") }
        _ = try WardrobeSpecifications.decode(item.specificationsJson)
        item.imageUrls = imagePaths
        item.sizeChartImageUrls = detailImagePaths
        item.sizeChartImageUrl = detailImagePaths.values.first
        return item
    }
    static func make(id: String, item: Item, baseline: Int64?) throws -> Self {
        var payload = item
        payload.imageUrls = StringList(); payload.sizeChartImageUrls = StringList(); payload.sizeChartImageUrl = nil
        return Self(id: id, targetItemId: item.id == 0 ? nil : item.id,
                    dataJson: String(decoding: try JSONEncoder().encode(payload), as: UTF8.self),
                    imagePaths: item.imageUrls, detailImagePaths: StringList(item.detailImagePaths), baselineUpdatedAt: baseline)
    }
}

enum WardrobeMigration {
    static func install(_ db: Database) throws {
        try db.alter(table: "categories") { $0.add(column: "categorySemantic", .text).notNull().defaults(to: "UNCONFIRMED") }
        try db.create(table: "storageNodes") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("locationId", .integer).notNull().references("locations", onDelete: .restrict)
            t.column("parentNodeId", .integer).references("storageNodes", onDelete: .restrict)
            t.column("name", .text).notNull(); t.column("description", .text).notNull().defaults(to: "")
            t.column("imageUrl", .text); t.column("sortOrder", .integer).notNull().defaults(to: 0)
            t.column("createdAt", .integer).notNull(); t.column("updatedAt", .integer).notNull()
        }
        try db.create(index: "index_storageNodes_location", on: "storageNodes", columns: ["locationId"])
        try db.create(index: "index_storageNodes_parent", on: "storageNodes", columns: ["parentNodeId"])
        try db.alter(table: "items") { t in
            t.add(column: "composition", .text).notNull().defaults(to: "UNCONFIRMED")
            t.add(column: "specificationsJson", .text).notNull().defaults(to: "")
            t.add(column: "sizeChartImageUrls", .text).notNull().defaults(to: "[]")
            t.add(column: "storageNodeId", .integer).references("storageNodes", onDelete: .restrict)
        }
        try db.create(index: "index_items_storageNode", on: "items", columns: ["storageNodeId"])
        try db.create(table: "itemDrafts") { t in
            t.primaryKey("id", .text)
            t.column("targetItemId", .integer).references("items", onDelete: .cascade).unique()
            t.column("dataJson", .text).notNull()
            t.column("imagePaths", .text).notNull(); t.column("detailImagePaths", .text).notNull()
            t.column("baselineUpdatedAt", .integer); t.column("updatedAt", .integer).notNull()
        }
        // Only new columns change. Legacy positions, pictures and business timestamps stay intact.
        for category in try Category.fetchAll(db) {
            try db.execute(sql: "UPDATE categories SET categorySemantic = ? WHERE id = ?", arguments: [CategorySemantic.historical(category.name).rawValue, category.id])
        }
    }
}
