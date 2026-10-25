import Foundation
@preconcurrency import GRDB

struct OrderImportSnapshot: Codable, Sendable, Equatable {
    var orders: [TaobaoOrder] = []
    var selectedKeys = Set<String>()
    var choices: [String: String] = [:]
    var step = TaobaoImportStep.select
    var missingAttributes: [TaobaoMissingAttribute] = []
    var result: TaobaoImportResult? = nil
}
struct LoadedOrderImport: Sendable {
    var session: OrderImportSession
    var snapshot: OrderImportSnapshot
    var drafts: [TaobaoImportDraft]
    var files: [OrderImportFile]
}
struct ImportSourceConflict: Identifiable, Sendable {
    var id: String { orderId }
    var orderId: String
    var versions: [TaobaoOrder]
}

final class OrderImportSessionRepository: Sendable {
    private let db: DatabaseQueue
    init(db: DatabaseQueue) { self.db = db }
    func sessions() async throws -> [OrderImportSession] { try await db.read { try OrderImportSession.filter(sql: "kind = 'orders'").order(sql: "updatedAt DESC").fetchAll($0) } }
    func load(_ id: String) async throws -> LoadedOrderImport {
        try await db.read { db in
            guard let session = try OrderImportSession.fetchOne(db, key: id), session.kind == "orders" else { throw ValidationError.invalid("导入会话不存在，请返回重新选择") }
            let snapshot = try JSONDecoder().decode(OrderImportSnapshot.self, from: Data(session.dataJson.utf8))
            let rows = try OrderImportRow.filter(sql: "sessionId = ?", arguments: [id]).order(sql: "position").fetchAll(db)
            let drafts = try rows.map { row in
                var value = try JSONDecoder().decode(TaobaoImportDraft.self, from: Data(row.dataJson.utf8))
                guard value.imagePath == nil else { throw ValidationError.invalid("导入草稿图片引用无效") }
                value.imagePath = row.imagePaths.values.first; return value
            }
            return LoadedOrderImport(session: session, snapshot: snapshot, drafts: drafts, files: try OrderImportFile.filter(sql: "sessionId = ?", arguments: [id]).fetchAll(db))
        }
    }
    func save(_ session: OrderImportSession, snapshot: OrderImportSnapshot, drafts: [TaobaoImportDraft], files: [OrderImportFile]) async throws -> OrderImportSession {
        var next = session; next.dataJson = try OrderImportSource.json(snapshot); next.revision += 1
        next.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
        let frozen = next
        let rows = try drafts.enumerated().map { index, draft -> OrderImportRow in
            var safe = draft; safe.imagePath = nil
            return OrderImportRow(id: session.id + ":" + draft.id, sessionId: session.id, position: index, sourceKey: draft.id, dataJson: try OrderImportSource.json(safe), imagePaths: StringList([draft.imagePath].compactMap { $0 }))
        }
        let previous = try await db.write { db -> [String] in
            let current = try OrderImportSession.fetchOne(db, key: session.id)
            guard current?.revision == session.revision || (current == nil && session.revision == 0) else { throw ValidationError.invalid("此会话已有更新，请重新读取草稿后继续") }
            let paths = try OrderImportRow.filter(sql: "sessionId = ?", arguments: [session.id]).fetchAll(db).flatMap(\.allImagePaths)
            try frozen.save(db)
            try db.execute(sql: "DELETE FROM orderImportRows WHERE sessionId = ?", arguments: [session.id])
            try db.execute(sql: "DELETE FROM orderImportFiles WHERE sessionId = ?", arguments: [session.id])
            for row in rows { try row.insert(db) }
            for file in files { guard file.sessionId == session.id else { throw ValidationError.invalid("文件不属于当前会话") }; try file.insert(db) }
            return paths
        }
        try? ImageFileHelper.deleteUnreferenced(paths: previous, db: db)
        return next
    }
    func discard(_ id: String) async throws {
        let paths = try await db.write { db -> [String] in
            let paths = try OrderImportRow.filter(sql: "sessionId = ?", arguments: [id]).fetchAll(db).flatMap(\.allImagePaths)
            try OrderImportSession.deleteOne(db, key: id); return paths
        }
        try? ImageFileHelper.deleteUnreferenced(paths: paths, db: db)
    }
    static func merge(_ files: [OrderImportFile], choices: [String: String]) -> (orders: [TaobaoOrder], conflicts: [ImportSourceConflict], duplicates: Int) {
        let grouped = Dictionary(grouping: files.flatMap(\.orders), by: \.orderId)
        var orders: [TaobaoOrder] = [], conflicts: [ImportSourceConflict] = [], duplicates = 0
        for key in grouped.keys.sorted() {
            var hashes = Set<String>()
            let versions = grouped[key, default: []].filter { hashes.insert(OrderImportSource.snapshot($0)).inserted }
            duplicates += grouped[key, default: []].count - versions.count
            if versions.count == 1 { orders += versions }
            else if let chosen = versions.first(where: { OrderImportSource.snapshot($0) == choices[key] }) { orders.append(chosen) }
            else { conflicts.append(ImportSourceConflict(orderId: key, versions: versions)) }
        }
        return (orders, conflicts, duplicates)
    }
    func commit(session: OrderImportSession, snapshot: OrderImportSnapshot, drafts: [TaobaoImportDraft]) async throws -> TaobaoImportResult {
        guard let operation = session.pendingOperationId else { throw ValidationError.invalid("提交标识缺失，请重试保存草稿") }
        let digest = OrderImportSource.hash(try OrderImportSource.json(snapshot) + OrderImportSource.json(drafts))
        return try await db.write { db in
            if let previous = try OrderImportCommit.fetchOne(db, key: operation) {
                guard previous.snapshotHash == digest else { throw ValidationError.invalid("提交内容已有变化，请重新核对") }
                return try JSONDecoder().decode(TaobaoImportResult.self, from: Data(previous.resultJson.utf8))
            }
            guard let saved = try OrderImportSession.fetchOne(db, key: session.id), saved.revision == session.revision, saved.pendingOperationId == operation,
                  saved.dataJson == (try OrderImportSource.json(snapshot)) else { throw ValidationError.invalid("导入会话已有更新，请重新读取后确认") }
            let storedRows = try OrderImportRow.filter(sql: "sessionId = ?", arguments: [session.id]).order(sql: "position").fetchAll(db)
            let persisted = try storedRows.map { row in var d = try JSONDecoder().decode(TaobaoImportDraft.self, from: Data(row.dataJson.utf8)); d.imagePath = row.imagePaths.values.first; return d }
            guard persisted == drafts else { throw ValidationError.invalid("商品草稿尚未完整保存，请重试保存后提交") }
            let selected = drafts.filter(\.included)
            guard !selected.isEmpty, Set(drafts.map(\.id)).count == drafts.count else { throw ValidationError.invalid("请选择商品并核对重复来源") }
            let sources = Dictionary(uniqueKeysWithValues: snapshot.orders.map { ($0.orderId, $0) })
            let receipts = try OrderImportReceipt.fetchAll(db)
            let oldItems = try Item.fetchAll(db)
            var accepted: [TaobaoImportDraft] = [], duplicates = 0, linked: [TaobaoImportDraft] = [], generations: [String: Int] = [:]
            for row in selected {
                guard let source = sources[row.original.orderId], row.sourceSnapshotHash == OrderImportSource.snapshot(source), row.original.sourceKey == row.id,
                      try OrderImportSource.units(source).contains(where: { $0.id == row.id }) else { throw ValidationError.invalid("商品来源发生变化，请重新选择订单") }
                let prior = receipts.filter { $0.sourceKey == row.id }.max { $0.generation < $1.generation }
                if let prior, prior.itemId != nil {
                    guard prior.sourceSnapshot == OrderImportSource.snapshot(source) || row.identityConfirmed else { throw ValidationError.invalid("已导入来源有变化，请先比较并确认；现有物品不会被覆盖") }
                    duplicates += 1; continue
                }
                if prior != nil && !row.allowDeletedReimport { throw ValidationError.invalid("此来源的原物品已删除，请明确确认重新导入，避免复建") }
                if oldItems.contains(where: { $0.importOrderKeys?.values.contains("\(row.original.orderId):\(row.original.lineIndex)") == true }), row.linkedItemId == nil {
                    throw ValidationError.invalid("此订单含旧版导入记录，请先关联现有物品，不能按新来源重复创建")
                }
                generations[row.id] = (prior?.generation ?? 0) + 1
                if let target = row.linkedItemId {
                    guard row.identityConfirmed, row.financialConfirmed, row.pairedWith == nil, try Item.fetchOne(db, key: target) != nil else { throw ValidationError.invalid("关联物品前请解除配对并确认来源身份") }
                    _ = try OrderImportSource.money(row.paidText); _ = try OrderImportSource.money(row.shippingText)
                    linked.append(row); continue
                }
                guard row.financialConfirmed else { throw ValidationError.invalid("请逐件核对商品金额、邮费与真实实付") }
                let merchandise = try OrderImportSource.money(row.priceText), shipping = try OrderImportSource.money(row.shippingText), paid = try OrderImportSource.money(row.paidText)
                guard paid <= merchandise + shipping else { throw ValidationError.invalid("实付不能超过当前阶段含邮费金额，请核对") }
                accepted.append(row)
            }
            // Any stale or partially skipped pair must fail before inserting a business record.
            let acceptedKeys = Set(accepted.map(\.id))
            guard accepted.allSatisfy({ $0.pairedWith == nil || acceptedKeys.contains($0.pairedWith!) }) else { throw ValidationError.invalid("配对的部分来源已处理，请解除配对后核对") }
            for (id, rows) in Dictionary(grouping: accepted + linked, by: { $0.original.orderId }) {
                guard let source = sources[id] else { throw ValidationError.invalid("订单来源缺失") }
                let prior = receipts.filter { $0.orderId == id && $0.itemId != nil }
                let paid = try rows.reduce(Int64(0)) { try $0 + OrderImportSource.money($1.paidText) } + prior.reduce(0) { $0 + $1.paidCents }
                let shipping = try rows.reduce(Int64(0)) { try $0 + OrderImportSource.money($1.shippingText) } + prior.reduce(0) { $0 + $1.shippingCents }
                if let cap = try? OrderImportSource.money(source.rawPaid ?? String(source.totalPaid)), paid > cap { throw ValidationError.invalid("订单累计实付超过来源，请核对分摊") }
                if let cap = try? OrderImportSource.money(source.rawShipping ?? String(source.shipping)), shipping > cap { throw ValidationError.invalid("订单累计邮费超过来源，请核对分摊") }
            }
            var result = TaobaoImportResult(duplicateCount: duplicates, omittedCount: drafts.count - selected.count)
            if !accepted.isEmpty { result = try TaobaoImportRepository.save(accepted, in: db, reviewed: true); result.duplicateCount += duplicates; result.omittedCount = drafts.count - selected.count }
            result.linkedCount = linked.count; result.commitId = operation
            try OrderImportCommit(id: operation, sessionId: session.id, revision: session.revision, snapshotHash: digest, resultJson: try OrderImportSource.json(result)).insert(db)
            let newItems = try Item.fetchAll(db)
            for row in accepted + linked {
                let itemId = row.linkedItemId ?? newItems.first(where: { $0.importOrderKeys?.values.contains(row.id) == true })?.id
                guard let itemId, let source = sources[row.original.orderId] else { throw ValidationError.invalid("导入结果无法核对") }
                try OrderImportReceipt(sourceKey: row.id, generation: generations[row.id]!, orderId: row.original.orderId, sourceSnapshot: OrderImportSource.snapshot(source), commitId: operation, itemId: itemId, paidCents: OrderImportSource.money(row.paidText), shippingCents: OrderImportSource.money(row.shippingText)).insert(db)
                var safe = row; safe.imagePath = nil
                try ItemSourceRecord(itemId: itemId, kind: "taobao-order", publicUrl: OrderImportSource.publicURL(row.original.productURL), snapshotJson: OrderImportSource.json(safe)).insert(db)
            }
            var completed = snapshot; completed.step = .result; completed.result = result
            var updated = saved; updated.revision += 1; updated.dataJson = try OrderImportSource.json(completed); updated.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
            try updated.update(db)
            return result
        }
    }
}
