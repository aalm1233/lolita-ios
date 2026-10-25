import Foundation
import GRDB

struct OrderImportSession: Codable, Sendable, FetchableRecord, PersistableRecord, Identifiable {
    var id: String = UUID().uuidString
    var revision: Int64 = 0
    var kind = "orders"
    var dataJson: String
    var pendingOperationId: String? = nil
    var createdAt = Int64(Date().timeIntervalSince1970 * 1000)
    var updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
    static let databaseTableName = "orderImportSessions"
}
struct OrderImportFile: Codable, Sendable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    var id = UUID().uuidString
    var sessionId: String
    var name: String
    var sha256: String
    var orders: [TaobaoOrder] { get { (try? JSONDecoder().decode([TaobaoOrder].self, from: Data(dataJson.utf8))) ?? [] } }
    var dataJson = "[]"
    var problem: String? = nil
    static let databaseTableName = "orderImportFiles"
}
struct OrderImportRow: Codable, Sendable, FetchableRecord, PersistableRecord, Identifiable {
    var id: String
    var sessionId: String
    var position: Int
    var sourceKey: String
    var dataJson: String
    var imagePaths: StringList
    var detailImagePaths = StringList()
    static let databaseTableName = "orderImportRows"
    var allImagePaths: [String] { imagePaths.values + detailImagePaths.values }
}
struct OrderImportCommit: Codable, Sendable, FetchableRecord, PersistableRecord, Identifiable {
    var id: String
    var sessionId: String?
    var revision: Int64
    var snapshotHash: String
    var resultJson: String
    var createdAt = Int64(Date().timeIntervalSince1970 * 1000)
    static let databaseTableName = "orderImportCommits"
}
struct OrderImportReceipt: Codable, Sendable, FetchableRecord, PersistableRecord, Identifiable {
    var id = UUID().uuidString
    var sourceKey: String
    var generation: Int
    var orderId: String
    var sourceSnapshot: String
    var commitId: String
    var itemId: Int64?
    var paidCents: Int64
    var shippingCents: Int64
    var createdAt = Int64(Date().timeIntervalSince1970 * 1000)
    static let databaseTableName = "orderImportReceipts"
}
struct ItemSourceRecord: Codable, Sendable, FetchableRecord, PersistableRecord, Identifiable {
    var id = UUID().uuidString
    var itemId: Int64
    var kind: String
    var publicUrl: String?
    var snapshotJson: String
    var appliedFields: StringList = StringList()
    var imagePaths: StringList = StringList()
    var createdAt = Int64(Date().timeIntervalSince1970 * 1000)
    static let databaseTableName = "itemSourceRecords"
}

enum OrderImportMigration {
    static let tables = ["orderImportSessions", "orderImportFiles", "orderImportRows", "orderImportCommits", "orderImportReceipts", "itemSourceRecords"]
    static func install(_ db: Database) throws {
        try db.create(table: "orderImportSessions") { t in
            t.primaryKey("id", .text); t.column("revision", .integer).notNull(); t.column("kind", .text).notNull()
            t.column("dataJson", .text).notNull(); t.column("pendingOperationId", .text)
            t.column("createdAt", .integer).notNull(); t.column("updatedAt", .integer).notNull()
        }
        try db.create(table: "orderImportFiles") { t in
            t.primaryKey("id", .text); t.column("sessionId", .text).notNull().indexed().references("orderImportSessions", onDelete: .cascade)
            t.column("name", .text).notNull(); t.column("sha256", .text).notNull(); t.column("dataJson", .text).notNull(); t.column("problem", .text)
        }
        try db.create(table: "orderImportRows") { t in
            t.primaryKey("id", .text); t.column("sessionId", .text).notNull().indexed().references("orderImportSessions", onDelete: .cascade)
            t.column("position", .integer).notNull(); t.column("sourceKey", .text).notNull(); t.column("dataJson", .text).notNull()
            t.column("imagePaths", .text).notNull(); t.column("detailImagePaths", .text).notNull(); t.uniqueKey(["sessionId", "position"])
        }
        try db.create(table: "orderImportCommits") { t in
            t.primaryKey("id", .text); t.column("sessionId", .text).indexed().references("orderImportSessions", onDelete: .setNull)
            t.column("revision", .integer).notNull(); t.column("snapshotHash", .text).notNull(); t.column("resultJson", .text).notNull(); t.column("createdAt", .integer).notNull()
        }
        try db.create(table: "orderImportReceipts") { t in
            t.primaryKey("id", .text); t.column("sourceKey", .text).notNull(); t.column("generation", .integer).notNull()
            t.column("orderId", .text).notNull().indexed(); t.column("sourceSnapshot", .text).notNull()
            t.column("commitId", .text).notNull().indexed().references("orderImportCommits", onDelete: .restrict)
            t.column("itemId", .integer).indexed().references("items", onDelete: .setNull)
            t.column("paidCents", .integer).notNull(); t.column("shippingCents", .integer).notNull(); t.column("createdAt", .integer).notNull()
            t.uniqueKey(["sourceKey", "generation"])
        }
        try db.create(table: "itemSourceRecords") { t in
            t.primaryKey("id", .text); t.column("itemId", .integer).notNull().indexed().references("items", onDelete: .cascade)
            t.column("kind", .text).notNull(); t.column("publicUrl", .text); t.column("snapshotJson", .text).notNull()
            t.column("appliedFields", .text).notNull(); t.column("imagePaths", .text).notNull(); t.column("createdAt", .integer).notNull()
        }
    }
}
