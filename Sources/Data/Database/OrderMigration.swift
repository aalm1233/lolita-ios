@preconcurrency import GRDB
import Foundation

enum OrderMigration {
    static func install(_ db: Database) throws {
        try db.alter(table: "items") { t in
            t.add(column: "parentItemId", .integer).references("items", onDelete: .restrict)
            t.add(column: "includedInParentPrice", .boolean).notNull().defaults(to: false)
        }
        try db.alter(table: "prices") { t in
            t.add(column: "shipping", .double).notNull().defaults(to: 0)
            t.add(column: "purchaseRecordStatus", .text).notNull().defaults(to: "NEEDS_REVIEW")
        }
        try db.create(table: "paymentStages") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("priceId", .integer).notNull().references("prices", onDelete: .cascade)
            t.column("name", .text).notNull()
            t.column("amount", .double).notNull()
            t.column("dueDate", .integer)
            t.column("reminderSet", .boolean).notNull().defaults(to: false)
            t.column("customReminderDays", .integer)
        }
        try db.create(index: "index_paymentStages_priceId", on: "paymentStages", columns: ["priceId"])
        try db.alter(table: "payments") { t in
            t.add(column: "stageId", .integer).references("paymentStages", onDelete: .setNull)
            t.add(column: "operationId", .text)
        }
        try db.create(index: "index_payments_operationId", on: "payments", columns: ["operationId"], unique: true)
        try db.create(table: "orderBindings") { t in
            t.column("itemId", .integer).primaryKey().references("items", onDelete: .cascade)
            t.column("priceId", .integer).notNull().unique().references("prices", onDelete: .restrict)
            t.column("purchaseRecordStatus", .text).notNull()
        }
        try backfill(db)
    }

    /// Copies plans and explicit ownership evidence. Never invents real payments or dates.
    /// Also used only when restoring a pre-ledger backup into the new schema.
    static func backfill(_ db: Database) throws {
        for price in try Price.fetchAll(db) {
            let records = try Payment.filter(Payment.Columns.priceId == price.id).order(Payment.Columns.id).fetchAll(db)
            for var record in records where record.stageId == nil {
                var stage = PaymentStage(priceId: price.id, name: "历史付款 \(record.id)", amount: record.amount,
                                         dueDate: record.dueDate, reminderSet: record.reminderSet,
                                         customReminderDays: record.customReminderDays)
                try stage.insert(db)
                // Only new columns change. All original ledger columns remain byte-for-byte meaningful.
                record.stageId = stage.id
                try db.execute(sql: "UPDATE payments SET stageId = ? WHERE id = ?", arguments: [stage.id, record.id])
            }
        }
        // Keep this historical migration independent of columns added by later versions.
        for row in try Row.fetchAll(db, sql: "SELECT id, status FROM items") {
            let itemId: Int64 = row["id"]
            let itemStatus: ItemStatus = row["status"]
            let prices = try Price.filter(Price.Columns.itemId == itemId).fetchAll(db)
            guard prices.count == 1, var price = prices.first,
                  (try? OrderAccounting.validate(price.totalPrice, positive: true)) != nil else { continue }
            let records = try Payment.filter(Payment.Columns.priceId == price.id).fetchAll(db)
            guard records.allSatisfy({ (try? OrderAccounting.validate($0.amount, positive: true)) != nil }),
                  itemStatus != .wished || records.contains(where: \.isPaid) else { continue }
            guard let paid = try? OrderAccounting.sum(records.filter(\.isPaid).map(\.amount)) else { continue }
            let status: PurchaseRecordStatus
            if paid > price.totalPrice { status = .needsReview }
            else if itemStatus == .owned && paid < price.totalPrice { status = .historicalOwned }
            else if records.isEmpty { status = .needsReview }
            else { status = .tracked }
            price.purchaseRecordStatus = status
            try price.update(db)
            try OrderBinding(itemId: itemId, priceId: price.id, purchaseRecordStatus: status).insert(db)
        }
    }
}
