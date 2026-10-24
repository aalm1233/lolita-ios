import GRDB
import Foundation

final class LolitaDatabase {
    let dbQueue: DatabaseQueue

    init(path: String, migrationTarget: String? = nil) throws {
        dbQueue = try DatabaseQueue(path: path)
        if let migrationTarget { try migrator.migrate(dbQueue, upTo: migrationTarget) }
        else { try migrator.migrate(dbQueue) }
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            // brands
            try db.create(table: "brands") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("isPreset", .boolean).notNull().defaults(to: false)
                t.column("logoUrl", .text)
                t.column("createdAt", .integer).notNull()
            }
            try db.create(index: "index_brands_name", on: "brands", columns: ["name"], unique: true)

            // categories
            try db.create(table: "categories") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("group", .text).notNull().defaults(to: "CLOTHING")
                t.column("isPreset", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .integer).notNull()
            }
            try db.create(index: "index_categories_name", on: "categories", columns: ["name"], unique: true)

            // styles
            try db.create(table: "styles") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("isPreset", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .integer).notNull()
            }
            try db.create(index: "index_styles_name", on: "styles", columns: ["name"], unique: true)

            // seasons
            try db.create(table: "seasons") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("isPreset", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .integer).notNull()
            }
            try db.create(index: "index_seasons_name", on: "seasons", columns: ["name"], unique: true)

            // sources
            try db.create(table: "sources") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("isPreset", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .integer).notNull()
            }
            try db.create(index: "index_sources_name", on: "sources", columns: ["name"], unique: true)

            // locations
            try db.create(table: "locations") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("description", .text).notNull().defaults(to: "")
                t.column("imageUrl", .text)
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .integer).notNull()
                t.column("updatedAt", .integer).notNull()
            }
            try db.create(index: "index_locations_name", on: "locations", columns: ["name"], unique: true)

            // coordinates
            try db.create(table: "coordinates") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("description", .text).notNull()
                t.column("imageUrls", .text).notNull().defaults(to: "[]")
                t.column("createdAt", .integer).notNull()
                t.column("updatedAt", .integer).notNull()
            }
            try db.create(index: "index_coordinates_name", on: "coordinates", columns: ["name"])
            try db.create(index: "index_coordinates_createdAt", on: "coordinates", columns: ["createdAt"])

            // outfitLogs
            try db.create(table: "outfitLogs") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("date", .integer).notNull()
                t.column("note", .text).notNull()
                t.column("imageUrls", .text).notNull().defaults(to: "[]")
                t.column("createdAt", .integer).notNull()
                t.column("updatedAt", .integer).notNull()
            }
            try db.create(index: "index_outfitLogs_date", on: "outfitLogs", columns: ["date"])
            try db.create(index: "index_outfitLogs_createdAt", on: "outfitLogs", columns: ["createdAt"])

            // outfitItemCrossRef
            try db.create(table: "outfitItemCrossRef") { t in
                t.column("outfitLogId", .integer).notNull()
                    .references("outfitLogs", column: "id", onDelete: .cascade)
                t.column("itemId", .integer).notNull()
                    .references("items", column: "id", onDelete: .cascade)
                t.primaryKey(["outfitLogId", "itemId"])
            }
            try db.create(index: "index_outfitItemCrossRef_outfitLogId", on: "outfitItemCrossRef", columns: ["outfitLogId"])
            try db.create(index: "index_outfitItemCrossRef_itemId", on: "outfitItemCrossRef", columns: ["itemId"])

            // items (last — references earlier tables)
            try db.create(table: "items") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("brandId", .integer).notNull()
                    .references("brands", column: "id", onDelete: .restrict)
                t.column("categoryId", .integer).notNull()
                    .references("categories", column: "id", onDelete: .restrict)
                t.column("status", .text).notNull().defaults(to: "OWNED")
                t.column("priority", .text).notNull().defaults(to: "MEDIUM")
                t.column("description", .text).notNull().defaults(to: "")
                t.column("colors", .text).notNull().defaults(to: "[]")
                t.column("season", .text)
                t.column("style", .text)
                t.column("size", .text)
                t.column("sizeChartImageUrl", .text)
                t.column("imageUrls", .text).notNull().defaults(to: "[]")
                t.column("coordinateId", .integer)
                    .references("coordinates", column: "id", onDelete: .restrict)
                t.column("coordinateOrder", .integer).notNull().defaults(to: 0)
                t.column("locationId", .integer)
                    .references("locations", column: "id", onDelete: .setNull)
                t.column("source", .text)
                t.column("createdAt", .integer).notNull()
                t.column("updatedAt", .integer).notNull()
            }
            try db.create(index: "index_items_name", on: "items", columns: ["name"])
            try db.create(index: "index_items_brandId", on: "items", columns: ["brandId"])
            try db.create(index: "index_items_categoryId", on: "items", columns: ["categoryId"])
            try db.create(index: "index_items_status", on: "items", columns: ["status"])
            try db.create(index: "index_items_priority", on: "items", columns: ["priority"])
            try db.create(index: "index_items_coordinateId", on: "items", columns: ["coordinateId"])
            try db.create(index: "index_items_locationId", on: "items", columns: ["locationId"])
        }

        migrator.registerMigration("v2") { db in
            try db.create(table: "prices") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("itemId", .integer).notNull()
                    .references("items", column: "id", onDelete: .cascade)
                t.column("type", .text).notNull()
                t.column("totalPrice", .double).notNull()
                t.column("deposit", .double)
                t.column("balance", .double)
                t.column("createdAt", .integer).notNull()
            }
            try db.create(index: "index_prices_itemId", on: "prices", columns: ["itemId"])
            try db.create(index: "index_prices_type", on: "prices", columns: ["type"])

            try db.create(table: "payments") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("priceId", .integer).notNull()
                    .references("prices", column: "id", onDelete: .cascade)
                t.column("amount", .double).notNull()
                t.column("dueDate", .integer).notNull()
                t.column("isPaid", .integer).notNull().defaults(to: 0)
                t.column("paidDate", .integer)
                t.column("calendarEventId", .integer)
                t.column("reminderSet", .integer).notNull().defaults(to: 0)
                t.column("customReminderDays", .integer)
                t.column("createdAt", .integer).notNull()
            }
            try db.create(index: "index_payments_priceId", on: "payments", columns: ["priceId"])
            try db.create(index: "index_payments_dueDate", on: "payments", columns: ["dueDate"])
            try db.create(index: "index_payments_isPaid", on: "payments", columns: ["isPaid"])
        }

        migrator.registerMigration("v3-payment-status") { db in
            // Repair records successfully saved by the original iOS release with ID 0.
            // Copy first, move foreign keys, then remove the old row under normal FK checks.
            let repairs: [(String, [(String, String)])] = [
                ("brands", [("items", "brandId")]), ("categories", [("items", "categoryId")]),
                ("locations", [("items", "locationId")]), ("coordinates", [("items", "coordinateId")]),
                ("items", [("prices", "itemId"), ("outfitItemCrossRef", "itemId")]),
                ("prices", [("payments", "priceId")]), ("outfitLogs", [("outfitItemCrossRef", "outfitLogId")]),
                ("styles", []), ("seasons", []), ("sources", [])
            ]
            for (table, references) in repairs {
                guard try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM \(table) WHERE id = 0)") == true else { continue }
                let uniqueName = ["brands", "categories", "locations", "styles", "seasons", "sources"].contains(table)
                if uniqueName { try db.execute(sql: "DROP INDEX index_\(table)_name") }
                let columns = try Row.fetchAll(db, sql: "PRAGMA table_info(\(table))")
                    .compactMap { $0["name"] as String? }.filter { $0 != "id" }
                    .map { "\"" + $0 + "\"" }.joined(separator: ", ")
                try db.execute(sql: "INSERT INTO \(table)(\(columns)) SELECT \(columns) FROM \(table) WHERE id = 0")
                let id = db.lastInsertedRowID
                for (child, column) in references {
                    try db.execute(sql: "UPDATE \(child) SET \(column) = ? WHERE \(column) = 0", arguments: [id])
                }
                try db.execute(sql: "DELETE FROM \(table) WHERE id = 0")
                if uniqueName { try db.create(index: "index_\(table)_name", on: table, columns: ["name"], unique: true) }
            }
            try db.execute(sql: """
                UPDATE items SET status = CASE WHEN EXISTS (
                    SELECT 1 FROM payments pay JOIN prices pr ON pay.priceId = pr.id
                    WHERE pr.itemId = items.id AND pr.type = 'DEPOSIT_BALANCE' AND pay.isPaid = 0
                ) THEN 'PENDING_BALANCE' ELSE 'OWNED' END
                WHERE status IN ('OWNED', 'PENDING_BALANCE')
                """)
        }

        migrator.registerMigration("v4-import-order-keys") { db in
            try db.alter(table: "items") { t in t.add(column: "importOrderKeys", .text) }
        }

        migrator.registerMigration("v5-order-ledger") { @Sendable db in
            try OrderMigration.install(db)
        }

        migrator.registerMigration("v6-after-sale-budget") { @Sendable db in
            try AfterSaleMigration.install(db)
        }

        migrator.registerMigration("v7-wardrobe-storage") { @Sendable db in
            try WardrobeMigration.install(db)
        }

        return migrator
    }
}
