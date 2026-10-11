@preconcurrency import GRDB
import Foundation

struct Item: Codable, Sendable, FetchableRecord, MutablePersistableRecord {
    var id: Int64 = 0
    var name: String
    var brandId: Int64
    var categoryId: Int64
    var status: ItemStatus = .owned
    var priority: ItemPriority = .medium
    var description: String = ""
    var colors: StringList = StringList()
    var season: String? = nil
    var style: String? = nil
    var size: String? = nil
    var sizeChartImageUrl: String? = nil
    var imageUrls: StringList = StringList()
    var coordinateId: Int64? = nil
    var coordinateOrder: Int = 0
    var locationId: Int64? = nil
    var source: String? = nil
    var createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    var updatedAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)

    static let databaseTableName = "items"

    enum Columns: String, ColumnExpression {
        case id, name, brandId, categoryId, status, priority, description
        case colors, season, style, size, sizeChartImageUrl, imageUrls
        case coordinateId, coordinateOrder, locationId, source
        case createdAt, updatedAt
    }

    // Room treats 0 as an unset ID; SQLite/GRDB needs NULL to generate one.
    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id == 0 ? nil : id
        container["name"] = name
        container["brandId"] = brandId
        container["categoryId"] = categoryId
        container["status"] = status
        container["priority"] = priority
        container["description"] = description
        container["colors"] = colors
        container["season"] = season
        container["style"] = style
        container["size"] = size
        container["sizeChartImageUrl"] = sizeChartImageUrl
        container["imageUrls"] = imageUrls
        container["coordinateId"] = coordinateId
        container["coordinateOrder"] = coordinateOrder
        container["locationId"] = locationId
        container["source"] = source
        container["createdAt"] = createdAt
        container["updatedAt"] = updatedAt
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    static let brand = belongsTo(Brand.self)
    static let category = belongsTo(Category.self)
    static let coordinate = belongsTo(Coordinate.self)
    static let location = belongsTo(Location.self)

    var brand: QueryInterfaceRequest<Brand> {
        request(for: Item.brand)
    }
    var category: QueryInterfaceRequest<Category> {
        request(for: Item.category)
    }
    var coordinate: QueryInterfaceRequest<Coordinate> {
        request(for: Item.coordinate)
    }
    var location: QueryInterfaceRequest<Location> {
        request(for: Item.location)
    }
}
