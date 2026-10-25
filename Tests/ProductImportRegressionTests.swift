import XCTest
@preconcurrency import GRDB
@testable import lolita

final class ProductImportRegressionTests: XCTestCase {
    private static func fixture() async throws -> (DatabaseQueue, Item) {
        let q = try LolitaDatabase(path: ":memory:").dbQueue
        return try await q.write { db in
            var b = Brand(name:"原品牌"); try b.insert(db); var c = Category(name:"JSK",categorySemantic:.jsk); try c.insert(db)
            var i = Item(name:"原服饰",brandId:b.id,categoryId:c.id,status:.owned,description:"保留说明",colors:StringList(["旧颜色"]),size:"旧尺码",importOrderKeys:StringList(["legacy-key"]),createdAt:111,updatedAt:222); try i.insert(db)
            var p = Price(itemId:i.id,type:.full,totalPrice:100); try p.insert(db)
            var pay = Payment(priceId:p.id,amount:100,dueDate:123,isPaid:true,paidDate:456); try pay.insert(db)
            return (q,i)
        }
    }
    private func staged(_ q: DatabaseQueue, item: Item, target: Int64? = nil) async throws -> LoadedProductImport {
        let repo = ProductImportRepository(db:q); var loaded = try await repo.load(target:target)
        loaded.snapshot.candidate = ProductCandidate(publicURL:"https://item.taobao.com/item.htm?id=123",name:"网页候选",properties:"棉 100%",selectedSKU:"蓝色 M")
        loaded.snapshot.name = "网页候选"; loaded.snapshot.properties = "棉 100%"; loaded.snapshot.confirmedSKU = true
        loaded.snapshot.brandId = item.brandId; loaded.snapshot.categoryId = item.categoryId
        loaded.session = try await repo.save(loaded.session,snapshot:loaded.snapshot,photos:loaded.photos,details:loaded.details)
        return loaded
    }
    private func eq<T: Equatable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) { XCTAssertEqual(a,b,file:file,line:line) }
    private func fails(_ action: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async { do { try await action(); XCTFail("应拒绝覆盖",file:file,line:line) } catch {} }
    func testProductParserRejectsDifferentProductFiltersImageHostsAndFlagsAmbiguousPrices() throws {
        let raw = #"{"url":"https://item.taobao.com/item.htm?id=123&spm=track","name":"网页标题","price":"100-200 起","sku":"蓝色 M","photos":["//img.alicdn.com/a.jpg","https://evil.test/a.jpg"],"details":["file:///tmp/a.jpg"],"properties":"棉"}"#
        let candidate = try ProductSource.parse(raw,expectedURL:"https://item.taobao.com/item.htm?id=123")
        eq(candidate.photoURLs,["https://img.alicdn.com/a.jpg"]); eq(candidate.detailURLs,[]); eq(candidate.warnings.count,1)
        XCTAssertThrowsError(try ProductSource.parse(raw,expectedURL:"https://item.taobao.com/item.htm?id=999"))
        eq(ProductSource.shareURL("淘宝分享 https://detail.tmall.com/item.htm?id=98&spm=secret 商品"),"https://detail.tmall.com/item.htm?id=98")
        XCTAssertNil(ProductSource.imageURL("https://alicdn.com.evil.test/a.jpg")); XCTAssertNil(ProductSource.imageURL("https://user@img.alicdn.com/a.jpg"))
    }
    func testProductBatchCreatesOnlyWishesAndIndependentZeroReferenceIdempotently() async throws {
        let (q,item) = try await Self.fixture(); let repo = ProductImportRepository(db:q); var loaded = try await staged(q,item:item)
        loaded.snapshot.variants = "蓝色 | M\n红色 | L"; loaded.snapshot.referenceText = "0"
        loaded.session = try await repo.save(loaded.session,snapshot:loaded.snapshot,photos:[],details:[])
        let first = try await repo.commit(loaded), second = try await repo.commit(loaded)
        eq(first,second); eq(first.savedItemIds.count,2)
        try await q.read { db in
            XCTAssertEqual(try Item.filter(Item.Columns.status == ItemStatus.wished.rawValue).fetchCount(db),2)
            XCTAssertEqual(try Price.fetchCount(db),1); XCTAssertEqual(try Payment.fetchCount(db),1); XCTAssertEqual(try OrderBinding.fetchCount(db),0)
            XCTAssertEqual(try ItemReferencePrice.fetchAll(db).map(\.amount),[0,0])
            let wishes = try Item.filter(Item.Columns.status == ItemStatus.wished.rawValue).order(Item.Columns.id).fetchAll(db)
            XCTAssertEqual(wishes.map(\.size),["M","L"]); XCTAssertEqual(wishes.map { $0.colors.values },[["蓝色"],["红色"]])
        }
    }
    func testSupplementOnlySelectedFieldsPreservesOriginalMoneyDataAndPhotos() async throws {
        let (q,item) = try await Self.fixture(); let repo = ProductImportRepository(db:q)
        let originalPath = try XCTUnwrap(ImageFileHelper.save(imageData:Data([1]))), candidatePath = try XCTUnwrap(ImageFileHelper.save(imageData:Data([2])))
        defer { ImageFileHelper.delete(paths:[originalPath,candidatePath]) }
        try await q.write { db in var i = item; i.imageUrls = StringList([originalPath]); try i.update(db) }
        var loaded = try await staged(q,item:item,target:item.id)
        loaded.snapshot.selectedFields = ["name","photos"]; loaded.snapshot.color = "不能覆盖"; loaded.photos = [candidatePath]
        loaded.session = try await repo.save(loaded.session,snapshot:loaded.snapshot,photos:loaded.photos,details:[])
        _ = try await repo.commit(loaded)
        try await q.read { db in
            let i = try XCTUnwrap(Item.fetchOne(db,key:item.id)); XCTAssertEqual(i.name,"网页候选"); XCTAssertEqual(i.size,"旧尺码"); XCTAssertEqual(i.colors.values,["旧颜色"])
            XCTAssertEqual(i.description,"保留说明"); XCTAssertEqual(i.status,.owned); XCTAssertEqual(i.importOrderKeys?.values,["legacy-key"]); XCTAssertEqual(i.createdAt,111)
            XCTAssertEqual(i.imageUrls.values,[originalPath,candidatePath]); XCTAssertEqual(try Payment.fetchOne(db)?.amount,100); XCTAssertEqual(try Payment.fetchOne(db)?.paidDate,456)
            XCTAssertEqual(try ItemSourceRecord.fetchOne(db)?.imagePaths.values,[candidatePath])
        }
        try ImageFileHelper.deleteUnreferenced(paths:[originalPath,candidatePath],db:q)
        XCTAssertTrue(FileManager.default.fileExists(atPath:originalPath)); XCTAssertTrue(FileManager.default.fileExists(atPath:candidatePath))
    }
    func testSupplementMergesExistingDraftWithoutOverwritingOriginalOrOtherInput() async throws {
        let (q,item) = try await Self.fixture(); var edited = item; edited.description = "尚未保存的说明"; edited.size = "自定义草稿尺码"
        let originalDraft = try ItemDraft.make(id:"item.\(item.id)",item:edited,baseline:item.updatedAt); try await ItemDraftRepository(db:q).save(originalDraft)
        let repo = ProductImportRepository(db:q); var loaded = try await staged(q,item:item,target:item.id)
        loaded.snapshot.selectedFields = ["name"]; loaded.session = try await repo.save(loaded.session,snapshot:loaded.snapshot,photos:[],details:[])
        let result = try await repo.commit(loaded); eq(result.returnedDraftId,originalDraft.id)
        let savedValue = try await ItemDraftRepository(db:q).get(originalDraft.id); let saved = try XCTUnwrap(savedValue); let merged = try saved.item()
        eq(merged.name,"网页候选"); eq(merged.size,"自定义草稿尺码"); eq(merged.description,"尚未保存的说明")
        eq(try await q.read { try Item.fetchOne($0,key:item.id)?.name },"原服饰")
    }
    func testSupplementRejectsConcurrentItemAndDraftChanges() async throws {
        let (q,item) = try await Self.fixture(); let repo = ProductImportRepository(db:q); var loaded = try await staged(q,item:item,target:item.id)
        loaded.snapshot.selectedFields = ["name"]; loaded.session = try await repo.save(loaded.session,snapshot:loaded.snapshot,photos:[],details:[])
        try await q.write { db in try db.execute(sql:"UPDATE items SET name='另处修改',updatedAt=333 WHERE id=?",arguments:[item.id]) }
        await fails { _ = try await repo.commit(loaded) }; eq(try await q.read { try Item.fetchOne($0,key:item.id)?.name },"另处修改")
        let (q2,i2) = try await Self.fixture(); let r2 = ProductImportRepository(db:q2)
        var draft = try ItemDraft.make(id:"editor",item:i2,baseline:i2.updatedAt); try await ItemDraftRepository(db:q2).save(draft)
        var current = try await staged(q2,item:i2,target:i2.id); current.snapshot.selectedFields = ["name"]; current.session = try await r2.save(current.session,snapshot:current.snapshot,photos:[],details:[])
        draft.imagePaths = StringList(["changed.jpg"]); try await ItemDraftRepository(db:q2).save(draft)
        await fails { _ = try await r2.commit(current) }
    }
    func testUnconfirmedProductAndDuplicateVariantsAreRejectedWithoutPartialInserts() async throws {
        let (q,item) = try await Self.fixture(); let repo = ProductImportRepository(db:q); var loaded = try await staged(q,item:item)
        loaded.snapshot.confirmedSKU = false; loaded.session = try await repo.save(loaded.session,snapshot:loaded.snapshot,photos:[],details:[])
        await fails { _ = try await repo.commit(loaded) }
        loaded.snapshot.confirmedSKU = true; loaded.snapshot.variants = "蓝色\n蓝色"; loaded.session = try await repo.save(loaded.session,snapshot:loaded.snapshot,photos:[],details:[])
        await fails { _ = try await repo.commit(loaded) }; eq(try await q.read { try Item.fetchCount($0) },1)
    }
    func testNewTablesRoundTripJSONZIPCSVWithDraftAndEvidenceImageProtection() async throws {
        let (q,item) = try await Self.fixture(); let repo = ProductImportRepository(db:q); var loaded = try await staged(q,item:item)
        let bytes = Data([4,5,6,7]), path = try XCTUnwrap(ImageFileHelper.save(imageData:Data([4,5,6,7]))); defer { ImageFileHelper.delete(path:path) }
        loaded.photos = [path]; loaded.session = try await repo.save(loaded.session,snapshot:loaded.snapshot,photos:loaded.photos,details:[])
        _ = try await repo.commit(loaded)
        let manager = BackupManager(db:q), data = try await manager.exportJSON(), before = try BackupManager.preview(data)
        eq(before.iosImportVersion,1); eq(before.orderImportSessions.count,1); eq(before.orderImportRows.count,1); eq(before.orderImportCommits.count,1); eq(before.itemSourceRecords.count,1)
        let target = try LolitaDatabase(path:":memory:").dbQueue; try await BackupManager(db:target).restore(before)
        let restored = try await BackupManager(db:target).snapshot()
        eq(restored.orderImportSessions[0].dataJson,before.orderImportSessions[0].dataJson); eq(restored.itemSourceRecords.count,1)
        for p in restored.imagePaths { eq(try Data(contentsOf:ImageFileHelper.fileURL(for:p)),bytes) }
        let zip = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip"); defer { try? FileManager.default.removeItem(at:zip) }
        try await manager.exportZIP().write(to:zip)
        let prepared = try BackupManager.prepare(at:zip); eq(prepared.backup.orderImportRows.count,1); eq(prepared.imageCount,1)
        let csv = String(decoding:try await manager.exportCSV(),as:UTF8.self); eq(csv.components(separatedBy:"=== ").count-1,26)
        for section in ["ORDER_IMPORT_SESSIONS","ORDER_IMPORT_FILES","ORDER_IMPORT_ROWS","ORDER_IMPORT_COMMITS","ORDER_IMPORT_RECEIPTS","ITEM_SOURCE_RECORDS"] { XCTAssertTrue(csv.contains("=== " + section + " ===")) }
        for p in restored.imagePaths { ImageFileHelper.delete(path:p) }
    }
    func testBackupRejectsMissingTablesFutureVersionsInvalidRelationshipsAndHiddenImages() async throws {
        let (q,item) = try await Self.fixture(); _ = try await staged(q,item:item)
        let manager = BackupManager(db:q), json = try await manager.exportJSON(); let root = try XCTUnwrap(JSONSerialization.jsonObject(with:json) as? [String:Any])
        for key in OrderImportMigration.tables { var missing = root; missing.removeValue(forKey:key); XCTAssertThrowsError(try BackupManager.preview(JSONSerialization.data(withJSONObject:missing))) }
        var future = root; future["iosImportVersion"] = 2; XCTAssertThrowsError(try BackupManager.preview(JSONSerialization.data(withJSONObject:future)))
        var invalid = try await manager.snapshot(); invalid.orderImportRows[0].sessionId = "absent"; XCTAssertThrowsError(try BackupManager.preview(JSONEncoder().encode(invalid)))
        var legacy = root; legacy.removeValue(forKey:"iosImportVersion"); for key in OrderImportMigration.tables { legacy.removeValue(forKey:key) }
        let old = try BackupManager.preview(JSONSerialization.data(withJSONObject:legacy)); eq(old.orderImportRows.count,0); eq(old.items.count,1)
    }
    func testImportEvidenceRelocatesWithoutChangingTimestampsOrJSON() async throws {
        let (q,item) = try await Self.fixture(); let repo = ProductImportRepository(db:q); var loaded = try await staged(q,item:item)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true); defer { try? FileManager.default.removeItem(at:directory) }
        let current = directory.appendingPathComponent("evidence.jpg"); try Data([1,2]).write(to:current)
        let old = "/var/mobile/Containers/Data/Application/11111111-2222-3333-4444-555555555555/Documents/images/evidence.jpg"
        loaded.photos = [old]; loaded.session = try await repo.save(loaded.session,snapshot:loaded.snapshot,photos:loaded.photos,details:[]); _ = try await repo.commit(loaded)
        let before = try await BackupManager(db:q).snapshot()
        _ = try ImageFileHelper.migrateStoredPaths(db:q,imagesDirectory:directory)
        let after = try await BackupManager(db:q).snapshot()
        eq(after.orderImportRows[0].imagePaths.values,[current.path]); eq(after.itemSourceRecords[0].imagePaths.values,[current.path])
        eq(after.orderImportSessions[0].dataJson,before.orderImportSessions[0].dataJson); eq(after.orderImportRows[0].dataJson,before.orderImportRows[0].dataJson)
        eq(after.itemSourceRecords[0].createdAt,before.itemSourceRecords[0].createdAt)
    }
    func testShortShareURLIsAllowedOnlyForWebResolutionAndPendingDetailsAreRejected() throws {
        eq(ProductSource.shareURL("分享 https://e.tb.cn/h.abc?tk=123 商品"),"https://e.tb.cn/h.abc?tk=123")
        XCTAssertNil(ProductSource.shareURL("https://e.tb.cn.evil.test/h.abc"))
        let raw = #"{"url":"https://item.taobao.com/item.htm?id=123","name":"公开商品","detailStatus":"complete"}"#
        eq(try ProductSource.parse(raw,expectedURL:"https://e.tb.cn/h.abc").publicURL,"https://item.taobao.com/item.htm?id=123")
        XCTAssertThrowsError(try ProductSource.parse(raw.replacingOccurrences(of:"complete",with:"pending"),expectedURL:"https://e.tb.cn/h.abc"))
    }
    @MainActor func testChangingProductInputRequiresNewConfirmationAndKeepsOriginalItem() async throws {
        let (q,item) = try await Self.fixture(); let model = ProductImportViewModel(target:item.id,db:q)
        await model.load(); model.state.input = "https://item.taobao.com/item.htm?id=123"; model.manualCandidate(); model.state.confirmedSKU = true
        model.changeInput("https://item.taobao.com/item.htm?id=456")
        XCTAssertNil(model.state.candidate); XCTAssertFalse(model.state.confirmedSKU)
        eq(try await q.read { try Item.fetchOne($0,key:item.id)?.name },"原服饰")
    }

    @MainActor func testRefreshingComparisonPreservesCandidateInputAndRequiresConfirmation() async throws {
        let (q,item) = try await Self.fixture(); let model = ProductImportViewModel(target:item.id,db:q)
        await model.load(); model.state.name = "尚未采用的候选"; model.state.confirmedSKU = true
        try await q.write { db in try db.execute(sql:"UPDATE items SET name='他处的新名称',updatedAt=444 WHERE id=?",arguments:[item.id]) }
        await model.refreshComparison()
        XCTAssertEqual(model.original?.name,"他处的新名称"); XCTAssertEqual(model.state.name,"尚未采用的候选")
        XCTAssertEqual(model.state.baselineUpdatedAt,444); XCTAssertFalse(model.state.confirmedSKU)
    }

    func testVariantSpecificReferencesAndSpecsStayExplicitAndRejectMalformedRows() throws {
        let rows = try ProductSource.variants("蓝色 | M | 0\n红色 | 定制 24.5 | 120.50",commonReference:"999")
        XCTAssertEqual(rows.map(\.referenceCents),[0,12050]); XCTAssertEqual(rows.map(\.size),["M","定制 24.5"])
        for raw in ["含糊规格", "蓝色 | M\n蓝色 | M | 30", "蓝色 | M | 定金 10"] { XCTAssertThrowsError(try ProductSource.variants(raw,commonReference:"")) }
    }

}
