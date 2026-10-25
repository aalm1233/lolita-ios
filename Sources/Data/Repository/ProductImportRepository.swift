import Foundation
@preconcurrency import GRDB

struct LoadedProductImport: Sendable {
    var session: OrderImportSession
    var snapshot: ProductImportSnapshot
    var photos: [String]
    var details: [String]
}
final class ProductImportRepository: Sendable {
    private let db: DatabaseQueue
    init(db: DatabaseQueue) { self.db = db }
    func load(target: Int64?) async throws -> LoadedProductImport {
        try await db.read { db in
            for session in try OrderImportSession.filter(sql: "kind = 'product'").order(sql: "updatedAt DESC").fetchAll(db) {
                let snapshot = try JSONDecoder().decode(ProductImportSnapshot.self, from: Data(session.dataJson.utf8))
                if snapshot.targetItemId == target && snapshot.savedItemIds.isEmpty && snapshot.returnedDraftId == nil {
                    let row = try OrderImportRow.filter(sql: "sessionId = ?", arguments: [session.id]).fetchOne(db)
                    return LoadedProductImport(session: session, snapshot: snapshot, photos: row?.imagePaths.values ?? [], details: row?.detailImagePaths.values ?? [])
                }
            }
            var snapshot = ProductImportSnapshot(targetItemId: target)
            var photos: [String] = [], details: [String] = []
            if let target {
                guard let item = try Item.fetchOne(db, key: target) else { throw ValidationError.invalid("物品已删除") }
                snapshot.baselineUpdatedAt = item.updatedAt; snapshot.name = item.name; snapshot.brandId = item.brandId; snapshot.categoryId = item.categoryId
                snapshot.color = item.colors.values.joined(separator: "、"); snapshot.size = item.size ?? ""
                if let draft = try ItemDraft.filter(sql: "targetItemId = ?", arguments: [target]).fetchOne(db) { snapshot.baselineDraftHash = ProductSource.draftFingerprint(draft) }
                let source = try ItemSourceRecord.filter(sql: "itemId = ?", arguments: [target]).order(sql: "createdAt DESC").fetchAll(db).first { $0.publicUrl != nil }
                snapshot.input = source?.publicUrl ?? ""
                // Existing photos are displayed by the comparison UI; candidate evidence is independent.
                photos = []; details = []
            }
            return LoadedProductImport(session: OrderImportSession(kind: "product", dataJson: try OrderImportSource.json(snapshot)), snapshot: snapshot, photos: photos, details: details)
        }
    }
    func save(_ session: OrderImportSession, snapshot: ProductImportSnapshot, photos: [String], details: [String]) async throws -> OrderImportSession {
        var next = session; next.revision += 1; next.dataJson = try OrderImportSource.json(snapshot); next.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
        let frozen = next
        let previous = try await db.write { db -> [String] in
            let old = try OrderImportSession.fetchOne(db, key: session.id)
            guard old?.revision == session.revision || (old == nil && session.revision == 0) else { throw ValidationError.invalid("商品草稿已在其他页面更新，请重新打开") }
            let row = try OrderImportRow.filter(sql: "sessionId = ?", arguments: [session.id]).fetchOne(db)
            try frozen.save(db)
            try OrderImportRow(id: session.id + ":product", sessionId: session.id, position: 0, sourceKey: "product", dataJson: "{}", imagePaths: StringList(photos), detailImagePaths: StringList(details)).save(db)
            return row?.allImagePaths ?? []
        }
        try? ImageFileHelper.deleteUnreferenced(paths: previous, db: db)
        return next
    }
    func commit(_ loaded: LoadedProductImport) async throws -> ProductImportSnapshot {
        let state = loaded.snapshot
        guard state.confirmedSKU, let candidate = state.candidate, OrderImportSource.publicURL(candidate.publicURL) == candidate.publicURL else { throw ValidationError.invalid("请先确认商品链接和本件颜色尺码") }
        return try await db.write { db in
            let digest = OrderImportSource.hash(try OrderImportSource.json(loaded.snapshot) + OrderImportSource.json(loaded.photos) + OrderImportSource.json(loaded.details))
            if let prior = try OrderImportCommit.fetchOne(db, key: state.operationId) {
                guard prior.snapshotHash == digest else { throw ValidationError.invalid("此提交已完成，请重新打开查看结果") }
                return try JSONDecoder().decode(ProductImportSnapshot.self, from: Data(prior.resultJson.utf8))
            }
            guard let session = try OrderImportSession.fetchOne(db, key: loaded.session.id), session.revision == loaded.session.revision, session.dataJson == (try OrderImportSource.json(state)) else { throw ValidationError.invalid("商品资料已有更新，请重新比较") }
            let evidence = try OrderImportRow.filter(sql: "sessionId = ?", arguments: [session.id]).fetchOne(db)
            guard evidence?.imagePaths.values == loaded.photos, evidence?.detailImagePaths.values == loaded.details else { throw ValidationError.invalid("商品图片已有变化，请先保存草稿") }
            var result = state
            if let target = state.targetItemId {
                guard let item = try Item.fetchOne(db, key: target), item.updatedAt == state.baselineUpdatedAt else { throw ValidationError.invalid("物品已有更新，原资料保留，请重新读取后比较") }
                let draft = try ItemDraft.filter(sql: "targetItemId = ?", arguments: [target]).fetchOne(db)
                guard draft.map(ProductSource.draftFingerprint) == state.baselineDraftHash else { throw ValidationError.invalid("编辑草稿已有变化，请先核对原草稿") }
                var base = try draft?.item() ?? item
                guard !state.selectedFields.isEmpty else { throw ValidationError.invalid("请至少选择一项补资料") }
                if state.selectedFields.contains("name") { base.name = try InputValidation.name(state.name) }
                if state.selectedFields.contains("brand") { base.brandId = state.brandId }
                if state.selectedFields.contains("category") { base.categoryId = state.categoryId }
                if state.selectedFields.contains("size") { base.size = state.size }
                if state.selectedFields.contains("colors") { base.colors = StringList(state.color.components(separatedBy: CharacterSet(charactersIn: "、，,")).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }) }
                if state.selectedFields.contains("properties") { base.description += "\n商品参数（用户选用）：\n" + state.properties }
                if state.selectedFields.contains("photos") { base.imageUrls = StringList(dedup(base.imageUrls.values + loaded.photos)) }
                if state.selectedFields.contains("details") { base.sizeChartImageUrls = StringList(dedup(base.detailImagePaths + loaded.details)); base.sizeChartImageUrl = base.sizeChartImageUrls.values.first }
                guard try Brand.fetchOne(db, key: base.brandId) != nil, try Category.fetchOne(db, key: base.categoryId) != nil else { throw ValidationError.invalid("请选择有效品牌和分类") }
                if let draft {
                    guard draft.baselineUpdatedAt == item.updatedAt else { throw ValidationError.invalid("原编辑草稿已过期，请先核对") }
                    let merged = try ItemDraft.make(id: draft.id, item: base, baseline: item.updatedAt)
                    try merged.update(db); result.returnedDraftId = draft.id
                } else {
                    base.updatedAt = max(item.updatedAt + 1, Int64(Date().timeIntervalSince1970 * 1000)); try base.update(db)
                    result.savedItemIds = [base.id]
                }
                try ItemSourceRecord(itemId: target, kind: draft == nil ? "product-supplement" : "product-supplement-draft", publicUrl: candidate.publicURL, snapshotJson: OrderImportSource.json(candidate), appliedFields: StringList(state.selectedFields.sorted()), imagePaths: StringList(loaded.photos + loaded.details)).insert(db)
            } else {
                guard try Brand.fetchOne(db, key: state.brandId) != nil, try Category.fetchOne(db, key: state.categoryId) != nil else { throw ValidationError.invalid("请选择品牌和分类") }
                let name = try InputValidation.name(state.name)
                let variants = try ProductSource.variants(state.variants, commonReference: state.referenceText)
                let reference = state.referenceText.isEmpty ? nil : try OrderImportSource.money(state.referenceText)
                let pieces = variants.isEmpty ? [ProductVariant(color: state.color, size: state.size, referenceCents: reference)] : variants
                for variant in pieces {
                    var item = Item(name: variants.isEmpty ? name : name + " · " + variant.title, brandId: state.brandId, categoryId: state.categoryId, status: .wished, description: state.properties, colors: StringList(variant.color.isEmpty ? [] : [variant.color]), size: variant.size.isEmpty ? nil : variant.size, imageUrls: StringList(loaded.photos), source: "淘宝商品链接")
                    item.sizeChartImageUrls = StringList(loaded.details); item.sizeChartImageUrl = loaded.details.first
                    try item.insert(db); result.savedItemIds.append(item.id)
                    if let reference = variant.referenceCents { try ItemReferencePrice(itemId: item.id, amount: Double(reference) / 100, note: "网页参考价，未建立订单").insert(db) }
                    try ItemSourceRecord(itemId: item.id, kind: "product-wish", publicUrl: candidate.publicURL, snapshotJson: OrderImportSource.json(candidate), appliedFields: StringList(["name", "properties", "photos", "details"]), imagePaths: StringList(loaded.photos + loaded.details)).insert(db)
                }
            }
            try OrderImportCommit(id: state.operationId, sessionId: session.id, revision: session.revision, snapshotHash: digest, resultJson: OrderImportSource.json(result)).insert(db)
            var next = session; next.dataJson = try OrderImportSource.json(result); next.revision += 1; try next.update(db)
            return result
        }
    }
}
private func dedup(_ paths: [String]) -> [String] { var seen = Set<String>(); return paths.filter { seen.insert(ImageFileHelper.fileURL(for: $0).absoluteString).inserted } }
