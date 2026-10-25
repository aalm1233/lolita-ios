import Foundation

enum ImportBackupValidation {
    static func validate(_ b: BackupData) throws {
        let empty = b.orderImportSessions.isEmpty && b.orderImportFiles.isEmpty && b.orderImportRows.isEmpty && b.orderImportCommits.isEmpty && b.orderImportReceipts.isEmpty && b.itemSourceRecords.isEmpty
        guard b.iosImportVersion == 1 || (b.iosImportVersion == nil && empty) else { throw ValidationError.invalid("导入会话备份版本无效") }
        for ids in [b.orderImportSessions.map(\.id), b.orderImportFiles.map(\.id), b.orderImportRows.map(\.id), b.orderImportCommits.map(\.id), b.orderImportReceipts.map(\.id), b.itemSourceRecords.map(\.id)] {
            guard ids.allSatisfy({ !$0.isEmpty && $0.count <= 250 }), Set(ids).count == ids.count else { throw ValidationError.invalid("导入记录 ID 无效或重复") }
        }
        let sessions = Dictionary(uniqueKeysWithValues: b.orderImportSessions.map { ($0.id, $0) })
        let commits = Set(b.orderImportCommits.map(\.id)), items = Set(b.items.map(\.id))
        var positions = Set<String>(), keys = Set<String>()
        for session in b.orderImportSessions {
            guard session.revision > 0, session.createdAt >= 0, session.updatedAt >= 0 else { throw ValidationError.invalid("导入会话版本或时间无效") }
            switch session.kind {
            case "orders":
                let value = try JSONDecoder().decode(OrderImportSnapshot.self, from: Data(session.dataJson.utf8))
                guard Set(value.orders.map(\.orderId)).count == value.orders.count else { throw ValidationError.invalid("导入来源重复") }
                for order in value.orders { _ = try OrderImportSource.units(order) }
            case "product":
                let value = try JSONDecoder().decode(ProductImportSnapshot.self, from: Data(session.dataJson.utf8))
                if let candidate = value.candidate { try validateCandidate(candidate) }
                if let hash = value.baselineDraftHash, !isHash(hash) { throw ValidationError.invalid("补资料草稿基准无效") }
            default: throw ValidationError.invalid("导入会话类型不受支持")
            }
        }
        for file in b.orderImportFiles {
            guard sessions[file.sessionId]?.kind == "orders", !file.name.isEmpty, file.sha256.count <= 100,
                  file.problem != nil || isHash(file.sha256) else { throw ValidationError.invalid("导入文件关联或摘要无效") }
            let orders = try JSONDecoder().decode([TaobaoOrder].self, from: Data(file.dataJson.utf8))
            for order in orders { _ = try OrderImportSource.units(order) }
        }
        for row in b.orderImportRows {
            guard let session = sessions[row.sessionId], row.position >= 0, positions.insert(row.sessionId + ":" + String(row.position)).inserted,
                  row.allImagePaths.allSatisfy({ !$0.isEmpty }) else { throw ValidationError.invalid("导入商品位置或图片无效") }
            if session.kind == "orders" {
                let value = try JSONDecoder().decode(TaobaoImportDraft.self, from: Data(row.dataJson.utf8))
                guard value.imagePath == nil, value.id == row.sourceKey else { throw ValidationError.invalid("导入草稿包含隐藏图片或错误来源") }
            } else { guard row.dataJson == "{}" else { throw ValidationError.invalid("商品草稿图片必须单独保存") } }
        }
        for commit in b.orderImportCommits {
            guard commit.sessionId == nil || sessions[commit.sessionId!] != nil, commit.revision > 0, isHash(commit.snapshotHash), commit.createdAt >= 0,
                  (try? JSONSerialization.jsonObject(with: Data(commit.resultJson.utf8))) != nil else { throw ValidationError.invalid("提交回执关联或摘要无效") }
        }
        for receipt in b.orderImportReceipts {
            guard commits.contains(receipt.commitId), receipt.itemId == nil || items.contains(receipt.itemId!), receipt.generation > 0,
                  !receipt.sourceKey.isEmpty, !receipt.orderId.isEmpty, isHash(receipt.sourceSnapshot), receipt.paidCents >= 0, receipt.shippingCents >= 0,
                  keys.insert(receipt.sourceKey + ":" + String(receipt.generation)).inserted else { throw ValidationError.invalid("来源回执关联、金额或代次无效") }
        }
        for source in b.itemSourceRecords {
            guard items.contains(source.itemId), source.createdAt >= 0, source.imagePaths.values.allSatisfy({ !$0.isEmpty }),
                  source.publicUrl == nil || OrderImportSource.publicURL(source.publicUrl!) == source.publicUrl else { throw ValidationError.invalid("来源资料关联或公开链接无效") }
            if source.kind == "taobao-order" {
                let value = try JSONDecoder().decode(TaobaoImportDraft.self, from: Data(source.snapshotJson.utf8))
                guard value.imagePath == nil else { throw ValidationError.invalid("来源快照不能隐藏本地图片引用") }
            } else if source.kind.hasPrefix("product-") { try validateCandidate(JSONDecoder().decode(ProductCandidate.self, from: Data(source.snapshotJson.utf8))) }
            else { throw ValidationError.invalid("来源资料类型不受支持") }
        }
    }
    private static func isHash(_ s: String) -> Bool { s.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil }
    private static func validateCandidate(_ c: ProductCandidate) throws {
        guard OrderImportSource.publicURL(c.publicURL) == c.publicURL, (c.photoURLs + c.detailURLs).allSatisfy({ ProductSource.imageURL($0)?.absoluteString == $0 }) else { throw ValidationError.invalid("商品来源包含不支持的链接") }
    }
}
