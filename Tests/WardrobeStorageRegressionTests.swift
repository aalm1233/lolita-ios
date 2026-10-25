import XCTest
@preconcurrency import GRDB
@testable import lolita

final class WardrobeStorageRegressionTests: XCTestCase {
    private static func fixture() async throws -> (DatabaseQueue, Item, Location, Location) {
        let q = try LolitaDatabase(path: ":memory:").dbQueue
        return try await q.write { db in
            var b = Brand(name: "登记品牌"); try b.insert(db)
            var c = Category(name: "鞋履分类", categorySemantic: .mary_jane); try c.insert(db)
            var a = Location(name: "卧室", createdAt: 11, updatedAt: 22); try a.insert(db)
            var z = Location(name: "衣帽间", createdAt: 33, updatedAt: 44); try z.insert(db)
            var i = Item(name: "登记样本", brandId: b.id, categoryId: c.id, locationId: a.id, importOrderKeys: StringList(["淘宝原订单"]), createdAt: 111, updatedAt: 222)
            try i.insert(db); return (q, i, a, z)
        }
    }
    private func fails(_ action: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do { try await action(); XCTFail("应拒绝无效操作", file: file, line: line) } catch {}
    }
    private func eq<T: Equatable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) { XCTAssertEqual(a,b,file:file,line:line) }
    private func unwrap<T>(_ value: T?) throws -> T { try XCTUnwrap(value) }
    private func image(_ bytes: Data = Data([1,2,3])) throws -> String { try XCTUnwrap(ImageFileHelper.save(imageData: bytes)) }

    func testV6UpgradePreservesEveryOriginalColumnAndImageAndIsIdempotent() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath:file) }
        let q = try LolitaDatabase(path:file,migrationTarget:"v6-after-sale-budget").dbQueue
        let picture = try image(); defer { ImageFileHelper.delete(path:picture) }
        let before = try q.write { db -> [String: [Row]] in
            try PresetData.seed(db)
            try db.execute(sql:"INSERT INTO locations(id,name,description,imageUrl,createdAt,updatedAt) VALUES(1,'旧房间','说明',?,111,222)",arguments:[picture])
            try db.execute(sql:"INSERT INTO items(id,name,brandId,categoryId,status,locationId,imageUrls,sizeChartImageUrl,importOrderKeys,createdAt,updatedAt) SELECT 1,'旧物品',(SELECT id FROM brands LIMIT 1),(SELECT id FROM categories LIMIT 1),'PENDING_REVIEW',1,?,?,?,111,222",arguments:[StringList([picture]),picture,StringList(["tb-key"])])
            try db.execute(sql:"INSERT INTO itemReferencePrices(itemId,amount,note,revision,updatedAt) VALUES(1,128,'旧参考价',1,333)")
            try db.execute(sql:"INSERT INTO prices(id,itemId,type,totalPrice,createdAt,shipping,purchaseRecordStatus) VALUES(1,1,'FULL',200,333,20,'TRACKED')")
            try db.execute(sql:"INSERT INTO paymentStages(id,priceId,name,amount,dueDate,reminderSet) VALUES(1,1,'旧阶段',200,NULL,0)")
            try db.execute(sql:"INSERT INTO payments(id,priceId,amount,dueDate,isPaid,paidDate,createdAt,stageId,operationId) VALUES(1,1,100,444,1,NULL,444,1,'old-paid')")
            try db.execute(sql:"INSERT INTO orderRefunds(id,priceId,amount,kind,receivedAt,note,operationId,createdAt) VALUES(1,1,25.25,'PRICE_DIFFERENCE',555,'原退差价','old-refund',555)")
            try db.execute(sql:"INSERT INTO orderCancellations(priceId,expectedRefundTotal,cancelledAt,note,revision) VALUES(1,100,666,'原取消约定',1)")
            try db.execute(sql:"INSERT INTO monthlyBudgets(month,amountCents,revision) VALUES('2026-10',500000,1)")
            return try Dictionary(uniqueKeysWithValues: Row.fetchAll(db,sql:"SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name != 'grdb_migrations'").map { row in
                let name: String = row["name"]; return (name,try Row.fetchAll(db,sql:"SELECT * FROM \"\(name)\" ORDER BY rowid"))
            })
        }
        try q.close()
        for _ in 0..<2 {
            let upgraded = try LolitaDatabase(path:file).dbQueue
            try upgraded.read { db in
                for (table,rows) in before {
                    let cols = rows.first?.columnNames.map { "\"\($0)\"" }.joined(separator:",") ?? "*"
                    XCTAssertEqual(try Row.fetchAll(db,sql:"SELECT \(cols) FROM \"\(table)\" ORDER BY rowid"),rows,table)
                }
                XCTAssertEqual(try StorageNode.fetchCount(db),0); XCTAssertEqual(try ItemDraft.fetchCount(db),0)
                XCTAssertEqual(try Item.fetchOne(db,key:1)?.sizeChartImageUrl,picture)
                XCTAssertTrue(try Row.fetchAll(db,sql:"PRAGMA foreign_key_check").isEmpty)
            }
            try upgraded.close()
        }
        XCTAssertEqual(try Data(contentsOf:URL(fileURLWithPath:picture)),Data([1,2,3]))
    }
    @MainActor func testCategoryRenameKeepsStableIdentityAndSpecifications() async throws {
        let (q,item,_,_) = try await Self.fixture()
        let vm = AttributeManageViewModel(db:q)
        try await vm.save(kind:.category,original:AttributeRow(id:item.categoryId,name:"鞋履分类",group:.accessory,semantic:.mary_jane),name:"梦幻改名",group:.accessory)
        let editor = ItemEditViewModel(db:q); await editor.load(itemId:item.id)
        XCTAssertEqual(editor.semantic,.mary_jane)
        editor.specifications.profiles["footwear"] = ["heelHeightCm":"3–5 cm", "sizeSystem":"JP"]
        editor.size = "定制 24.5"; editor.composition = .pair
        try await editor.save()
        let saved = try unwrap(try await ItemRepository(db:q).getById(item.id))
        XCTAssertEqual(saved.importOrderKeys?.values,["淘宝原订单"])
        XCTAssertEqual(try WardrobeSpecifications.decode(saved.specificationsJson).profiles["footwear"]?["heelHeightCm"],"3–5 cm")
        XCTAssertEqual(saved.composition,.pair); XCTAssertEqual(saved.size,"定制 24.5")
    }
    func testSpecificationsRetainRawRangesAndRejectUnknownOrFutureFields() throws {
        var s = WardrobeSpecifications(); s.profiles["wig"] = ["lengthCm":"40～60", "heatResistance":"≤ 120℃"]
        s.profiles["clothing"] = ["bustCm":"88–94"]
        XCTAssertEqual(try WardrobeSpecifications.decode(s.encoded()),s)
        for raw in ["{\"version\":2}","{\"version\":true}","{\"version\":1,\"unknown\":{}}","{\"version\":1,\"footwear\":{\"heelHeightCm\":4}}","{\"version\":1,\"clothing\":{\"madeUp\":\"x\"}}"] { XCTAssertThrowsError(try WardrobeSpecifications.decode(raw)) }
    }
    func testStorageRejectsDuplicateDepthCycleAndCrossRoomParentAtomically() async throws {
        let (q,_,a,b) = try await Self.fixture(); let repo = StorageRepository(db:q)
        let cabinet = try await repo.save(StorageNode(locationId:a.id,name:"衣柜"))
        let shelf = try await repo.save(StorageNode(locationId:a.id,parentNodeId:cabinet.id,name:"上层"))
        await fails { _ = try await repo.save(StorageNode(locationId:a.id,name:"  衣柜  ")) }
        await fails { _ = try await repo.save(StorageNode(locationId:a.id,parentNodeId:shelf.id,name:"太深")) }
        await fails { _ = try await repo.save(StorageNode(locationId:b.id,parentNodeId:cabinet.id,name:"错房间")) }
        await fails { try await repo.move(nodeId:cabinet.id,roomId:a.id,parentId:shelf.id) }
        eq(try await repo.getAll().count,2)
    }
    func testSubtreeMovePreservesItemDraftImagesBusinessFieldsAndTimestamps() async throws {
        let (q,item,a,b) = try await Self.fixture(); let repo = StorageRepository(db:q)
        let cabinet = try await repo.save(StorageNode(locationId:a.id,name:"柜架"))
        let shelf = try await repo.save(StorageNode(locationId:a.id,parentNodeId:cabinet.id,name:"层格"))
        let picture = try image(); defer { ImageFileHelper.delete(path:picture) }
        var placed = item; placed.storageNodeId = shelf.id; placed.imageUrls = StringList([picture]); placed.sizeChartImageUrls = StringList([picture]); let original = placed
        try await q.write { try original.update($0) }
        let draft = try ItemDraft.make(id:"item.\(item.id)",item:original,baseline:original.updatedAt)
        try await ItemDraftRepository(db:q).save(draft)
        try await repo.move(nodeId:cabinet.id,roomId:b.id,parentId:nil)
        let fresh = try unwrap(try await ItemRepository(db:q).getById(item.id))
        XCTAssertEqual(fresh.locationId,b.id); XCTAssertEqual(fresh.storageNodeId,shelf.id)
        XCTAssertEqual(fresh.updatedAt,222); XCTAssertEqual(fresh.createdAt,111)
        XCTAssertEqual(fresh.importOrderKeys?.values,["淘宝原订单"]); XCTAssertEqual(fresh.allImagePaths,original.allImagePaths)
        let resumed = try unwrap(try await ItemDraftRepository(db:q).get(draft.id))
        XCTAssertEqual(try resumed.item().locationId,b.id); XCTAssertEqual(resumed.updatedAt,draft.updatedAt)
        eq(StorageTree.path(roomId:b.id,nodeId:shelf.id,rooms:[a,b],nodes:try await repo.getAll()),"衣帽间 → 柜架 → 层格")
    }
    func testMovingCabinetWithChildUnderAnotherCabinetRollsBack() async throws {
        let (q,item,a,b) = try await Self.fixture(); let repo = StorageRepository(db:q)
        let cabinet = try await repo.save(StorageNode(locationId:a.id,name:"柜"))
        _ = try await repo.save(StorageNode(locationId:a.id,parentNodeId:cabinet.id,name:"层"))
        let target = try await repo.save(StorageNode(locationId:b.id,name:"目标柜"))
        await fails { try await repo.move(nodeId:cabinet.id,roomId:b.id,parentId:target.id) }
        eq(try await repo.getAll().first(where:{$0.id==cabinet.id})?.locationId,a.id)
        eq(try await ItemRepository(db:q).getById(item.id)?.locationId,a.id)
    }
    func testDeleteRequiresExplicitClearAndKeepsItemAndSharedPhotos() async throws {
        let (q,item,a,_) = try await Self.fixture(); let repo = StorageRepository(db:q)
        let photo = try image(); defer { ImageFileHelper.delete(path:photo) }
        let node = try await repo.save(StorageNode(locationId:a.id,name:"柜",imageUrl:photo))
        let original = item
        try await q.write { db in var i = original; i.storageNodeId=node.id; i.imageUrls=StringList([photo]); try i.update(db) }
        await fails { try await repo.delete(nodeId:node.id) }
        try await repo.delete(nodeId:node.id,clearContents:true)
        let saved = try unwrap(try await ItemRepository(db:q).getById(item.id))
        XCTAssertNil(saved.locationId); XCTAssertNil(saved.storageNodeId); XCTAssertEqual(saved.name,item.name)
        XCTAssertTrue(FileManager.default.fileExists(atPath:photo))
    }
    func testRoomDeleteClearsNodesAndDraftPlacementButKeepsItem() async throws {
        let (q,item,a,_) = try await Self.fixture(); let repo = StorageRepository(db:q)
        let node = try await repo.save(StorageNode(locationId:a.id,name:"柜"))
        try await repo.setMembership(nodeId:node.id,originalIds:[],selectedIds:[item.id])
        let placed = try unwrap(try await ItemRepository(db:q).getById(item.id))
        try await ItemDraftRepository(db:q).save(ItemDraft.make(id:"draft",item:placed,baseline:222))
        await fails { try await repo.deleteRoom(a) }
        try await repo.deleteRoom(a,clearContents:true)
        eq(try await repo.getAll().count,0)
        eq(try await ItemRepository(db:q).getById(item.id)?.name,item.name)
        let resumed = try unwrap(try await ItemDraftRepository(db:q).get("draft"))
        XCTAssertNil(try resumed.item().locationId); XCTAssertNil(try resumed.item().storageNodeId)
    }
    func testOnlyOwnedItemsCanBeNewlyPlacedButLegacyUnownedPlacementSurvivesEdit() async throws {
        let (q,item,a,_) = try await Self.fixture(); let repo=ItemRepository(db:q)
        let legacy = try await q.write { db -> Item in var i=item; i.status = .wished; try i.update(db); return i }
        var changed=legacy; changed.description="只改备注"; let updated=changed
        try await repo.update(updated)
        eq(try await repo.getById(item.id)?.locationId,a.id)
        await fails { _ = try await repo.insert(Item(name:"心愿新物",brandId:item.brandId,categoryId:item.categoryId,status:.wished,locationId:a.id)) }
    }
    func testSharedChildCannotBypassUnownedParentStorageRestriction() async throws {
        let (q,item,a,_) = try await Self.fixture()
        try await q.write { db in var parent = item; parent.status = .wished; try parent.update(db) }
        await fails {
            _ = try await ItemRepository(db:q).insert(Item(name:"共价新物品",brandId:item.brandId,categoryId:item.categoryId,locationId:a.id,parentItemId:item.id,includedInParentPrice:true))
        }
        eq(try await ItemRepository(db:q).getAll().count,1)
    }
    func testDeletingNewLocationDoesNotClearAnotherNodesMembers() async throws {
        let (q,item,a,_) = try await Self.fixture(); let repo = StorageRepository(db:q)
        let other = try await ItemRepository(db:q).insert(Item(name:"另一件物品",brandId:item.brandId,categoryId:item.categoryId))
        let first = try await repo.save(StorageNode(locationId:a.id,name:"原柜架"))
        let temporary = try await repo.save(StorageNode(locationId:a.id,name:"临时柜架"))
        try await repo.setMembership(nodeId:first.id,originalIds:[],selectedIds:[item.id])
        try await repo.setMembership(nodeId:temporary.id,originalIds:[],selectedIds:[other.id])
        try await repo.delete(nodeId:temporary.id,clearContents:true)
        eq(try await ItemRepository(db:q).getById(item.id)?.storageNodeId,first.id)
        eq(try await ItemRepository(db:q).getById(item.id)?.locationId,a.id)
        eq(try await ItemRepository(db:q).getById(other.id)?.storageNodeId,nil)
        eq(try await ItemRepository(db:q).getAll().count,2)
    }
    func testMembershipFailureRollsBackAllSelectedItems() async throws {
        let (q,item,a,_) = try await Self.fixture(); let repo=StorageRepository(db:q)
        let wish=try await ItemRepository(db:q).insert(Item(name:"未拥有",brandId:item.brandId,categoryId:item.categoryId,status:.wished))
        let node=try await repo.save(StorageNode(locationId:a.id,name:"柜"))
        await fails { try await repo.setMembership(nodeId:node.id,originalIds:[],selectedIds:[item.id,wish.id]) }
        eq(try await ItemRepository(db:q).getById(item.id)?.storageNodeId,nil)
    }
    @MainActor func testDraftRestoresAllRegistrationFieldsCoverAndImagesAfterNewEditor() async throws {
        let (q,_,_,_) = try await Self.fixture()
        let one=try image(), two=try image(Data([4,5,6])); defer { ImageFileHelper.delete(paths:[one,two]) }
        let editor=ItemEditViewModel(db:q); await editor.load(itemId:0)
        editor.name="未完成登记"; editor.size="定制 M+"; editor.composition = .set
        editor.imageUrls=[one,two]; editor.setCover(at:1); editor.sizeChartImageUrls=[one,two]
        editor.specifications.profiles["footwear"]=["heelHeightCm":"5～7"]
        try await editor.persistDraft()
        let recovered=ItemEditViewModel(db:q); await recovered.load(itemId:0)
        XCTAssertNotNil(recovered.pendingDraft); try recovered.resumeDraft()
        XCTAssertEqual(recovered.name,"未完成登记"); XCTAssertEqual(recovered.imageUrls,[two,one]); XCTAssertEqual(recovered.detailImages,[one,two]); XCTAssertEqual(recovered.composition,.set)
        XCTAssertEqual(recovered.size,"定制 M+"); XCTAssertEqual(recovered.specifications.profiles["footwear"]?["heelHeightCm"],"5～7")
        try await recovered.save()
        eq(try await ItemDraftRepository(db:q).get("new.OWNED")?.id,nil)
        eq(try await ItemRepository(db:q).getAll().first(where:{$0.name=="未完成登记"})?.imageUrls.values,[two,one])
    }
    @MainActor func testStaleDraftCannotOverwriteOtherSavedChangesAndRemainsRecoverable() async throws {
        let (q,item,_,_)=try await Self.fixture(); let first=ItemEditViewModel(db:q); await first.load(itemId:item.id)
        first.name="草稿名"; try await first.persistDraft()
        var changed=item; changed.name="其他页面已保存"; let submitted=changed
        try await ItemRepository(db:q).update(submitted)
        let resumed=ItemEditViewModel(db:q); await resumed.load(itemId:item.id); try resumed.resumeDraft()
        do { try await resumed.save(); XCTFail("过期草稿不能覆盖新数据") } catch {}
        eq(try await ItemRepository(db:q).getById(item.id)?.name,"其他页面已保存")
        eq(try await ItemDraftRepository(db:q).get("item.\(item.id)")?.id,"item.\(item.id)")
    }
    @MainActor func testDiscardDraftProtectsCommittedAndOtherDraftSharedImages() async throws {
        let (q,item,_,_)=try await Self.fixture(); let shared=try image(), unique=try image(Data([8])); defer { ImageFileHelper.delete(paths:[shared,unique]) }
        var other=Item(name:"别的草稿",brandId:item.brandId,categoryId:item.categoryId); other.imageUrls=StringList([shared])
        try await ItemDraftRepository(db:q).save(ItemDraft.make(id:"other",item:other,baseline:nil))
        let editor=ItemEditViewModel(db:q); await editor.load(itemId:item.id); editor.name="取消编辑"; editor.imageUrls=[shared,unique]
        try await editor.persistDraft(); try await editor.discardDraft()
        XCTAssertTrue(FileManager.default.fileExists(atPath:shared)); XCTAssertFalse(FileManager.default.fileExists(atPath:unique))
        eq(try await ItemRepository(db:q).getById(item.id)?.name,item.name)
    }
    @MainActor func testMultipleDetailsRemovalOnCancelKeepsOriginalsAndDiscardCleansNewFiles() async throws {
        let (q,item,_,_)=try await Self.fixture(); let old=try image(); defer { ImageFileHelper.delete(path:old) }
        try await q.write { db in var i=item; i.sizeChartImageUrl=old; i.sizeChartImageUrls=StringList([old]); try i.update(db) }
        let editor=ItemEditViewModel(db:q); await editor.load(itemId:item.id); editor.addDetailImageData(Data([4]))
        let added=try unwrap(editor.detailImages.last); defer { ImageFileHelper.delete(path:added) }
        editor.removeDetailImage(at:0); try await editor.persistDraft(); try await editor.discardDraft()
        XCTAssertTrue(FileManager.default.fileExists(atPath:old)); XCTAssertFalse(FileManager.default.fileExists(atPath:added))
        eq(try await ItemRepository(db:q).getById(item.id)?.sizeChartImageUrl,old)
    }
    func testJSONZIPAndCSVPreserveNewFieldsNodesDraftsAndEveryImage() async throws {
        let (q,item,a,_)=try await Self.fixture(); let bytes=Data([1,8,3,9]), photo=try image(bytes); defer { ImageFileHelper.delete(path:photo) }
        let node=try await StorageRepository(db:q).save(StorageNode(locationId:a.id,name:"柜",imageUrl:photo))
        var changed=item; changed.storageNodeId=node.id; changed.composition = .pair; changed.specificationsJson="{\"version\":1,\"footwear\":{\"heelHeightCm\":\"5–8\"}}"; changed.sizeChartImageUrls=StringList([photo]); changed.imageUrls=StringList([photo]); let submitted=changed
        try await ItemRepository(db:q).update(submitted)
        try await ItemDraftRepository(db:q).save(ItemDraft.make(id:"draft",item:submitted,baseline:222))
        let manager=BackupManager(db:q), json=try await manager.exportJSON(), original=try await manager.snapshot()
        XCTAssertEqual(original.iosWardrobeVersion,1); XCTAssertEqual(original.imagePaths,[photo])
        let target=try LolitaDatabase(path:":memory:").dbQueue, restore=BackupManager(db:target)
        try await restore.restore(BackupManager.preview(json))
        let copied=try await restore.snapshot(); defer { ImageFileHelper.delete(paths:Array(copied.imagePaths)) }
        XCTAssertEqual(copied.storageNodes.first?.name,"柜"); XCTAssertEqual(copied.items.first?.composition,.pair)
        XCTAssertEqual(copied.itemDrafts.count,1); XCTAssertEqual(try copied.itemDrafts[0].item().storageNodeId,node.id)
        for path in copied.imagePaths { XCTAssertEqual(try Data(contentsOf:ImageFileHelper.fileURL(for:path)),bytes) }
        let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".zip"); defer { try? FileManager.default.removeItem(at:file) }
        try await manager.exportZIP().write(to:file)
        try await restore.restore(BackupManager.prepare(at:file))
        let zipped=try await restore.snapshot(); defer { ImageFileHelper.delete(paths:Array(zipped.imagePaths)) }
        XCTAssertEqual(zipped.items.first?.specificationsJson,submitted.specificationsJson)
        XCTAssertEqual(zipped.itemDrafts.first?.baselineUpdatedAt,222)
        for path in zipped.imagePaths { XCTAssertEqual(try Data(contentsOf:ImageFileHelper.fileURL(for:path)),bytes) }
        let csv=String(decoding:try await manager.exportCSV(),as:UTF8.self)
        XCTAssertTrue(csv.contains("=== STORAGE_NODES ===")); XCTAssertTrue(csv.contains("=== ITEM_DRAFTS ===")); XCTAssertTrue(csv.contains("category_semantic")); XCTAssertTrue(csv.contains("size_chart_image_urls"))
    }
    func testBackupRejectsInvalidStorageGraphMissingTablesAndFutureVersions() async throws {
        let (q,_,a,_)=try await Self.fixture(); let manager=BackupManager(db:q)
        _=try await StorageRepository(db:q).save(StorageNode(locationId:a.id,name:"柜"))
        let json=try await manager.exportJSON(); let root=try unwrap(JSONSerialization.jsonObject(with:json) as? [String:Any])
        var missing=root; missing.removeValue(forKey:"itemDrafts")
        XCTAssertThrowsError(try BackupManager.preview(JSONSerialization.data(withJSONObject:missing)))
        var future=root; future["iosWardrobeVersion"]=2
        XCTAssertThrowsError(try BackupManager.preview(JSONSerialization.data(withJSONObject:future)))
        var invalid=try await manager.snapshot(); invalid.storageNodes[0].parentNodeId=invalid.storageNodes[0].id
        await fails { try await manager.restore(invalid) }
        eq(try await manager.snapshot().storageNodes.count,1)
        var unversioned=root; unversioned.removeValue(forKey:"iosWardrobeVersion")
        XCTAssertThrowsError(try BackupManager.preview(JSONSerialization.data(withJSONObject:unversioned)))
    }
    func testRelocationCoversDetailsNodesDraftsWithoutChangingBusinessTimestamps() async throws {
        let (q,item,a,_)=try await Self.fixture()
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("images")
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true); defer { try? FileManager.default.removeItem(at:dir.deletingLastPathComponent()) }
        try Data([4,5,6]).write(to:dir.appendingPathComponent("old.jpg"))
        let old="/private/var/mobile/Containers/Data/Application/\(UUID().uuidString)/Documents/images/old.jpg"
        let node=try await StorageRepository(db:q).save(StorageNode(locationId:a.id,name:"柜",imageUrl:old))
        var changed=item; changed.storageNodeId=node.id; changed.sizeChartImageUrls=StringList([old]); changed.imageUrls=StringList([old]); let placed=changed
        try await q.write { try placed.update($0) }
        try await ItemDraftRepository(db:q).save(ItemDraft.make(id:"draft",item:placed,baseline:222))
        try ImageFileHelper.migrateStoredPaths(db:q,imagesDirectory:dir)
        let snapshot=try await BackupManager(db:q).snapshot()
        XCTAssertEqual(snapshot.imagePaths,[dir.appendingPathComponent("old.jpg").path])
        XCTAssertEqual(snapshot.items[0].updatedAt,222); XCTAssertEqual(snapshot.items[0].createdAt,111)
        XCTAssertEqual(snapshot.itemDrafts[0].baselineUpdatedAt,222)
        try ImageFileHelper.deleteUnreferenced(paths:[old],db:q,imagesDirectory:dir)
        XCTAssertTrue(FileManager.default.fileExists(atPath:dir.appendingPathComponent("old.jpg").path))
    }
    @MainActor func testRevertingAllChangesClearsPersistedDraft() async throws {
        let (q,item,_,_) = try await Self.fixture()
        let editor = ItemEditViewModel(db:q); await editor.load(itemId:item.id)
        editor.name = "临时改名"; try await editor.persistDraft()
        eq(try await ItemDraftRepository(db:q).get("item.\(item.id)")?.targetItemId,item.id)
        editor.name = item.name; XCTAssertFalse(editor.hasChanges)
        try await editor.persistDraft()
        eq(try await ItemDraftRepository(db:q).get("item.\(item.id)")?.id,nil)
        eq(try await ItemRepository(db:q).getById(item.id)?.name,item.name)
    }
    func testDeletingItemCleansItsDraftOnlyFilesAndProtectsSharedImages() async throws {
        let (q,item,a,_)=try await Self.fixture(); let shared=try image(), draftOnly=try image(Data([9])); defer { ImageFileHelper.delete(paths:[shared,draftOnly]) }
        _=try await StorageRepository(db:q).save(StorageNode(locationId:a.id,name:"柜",imageUrl:shared))
        var draftItem=item; draftItem.imageUrls=StringList([shared,draftOnly])
        try await ItemDraftRepository(db:q).save(ItemDraft.make(id:"draft",item:draftItem,baseline:222))
        try await ItemRepository(db:q).delete(item)
        XCTAssertTrue(FileManager.default.fileExists(atPath:shared)); XCTAssertFalse(FileManager.default.fileExists(atPath:draftOnly))
        eq(try await ItemDraftRepository(db:q).get("draft")?.id,nil)
    }
    func testImportPlacementIsAtomicAndDoesNotRewriteUnrelatedEditorDrafts() async throws {
        let (q,item,a,b) = try await Self.fixture(); let repo = StorageRepository(db:q)
        let other = try await q.write { db in var i = Item(name:"另一个草稿物品",brandId:item.brandId,categoryId:item.categoryId,status:.wished); try i.insert(db); return i }
        try await ItemDraftRepository(db:q).save(ItemDraft.make(id:"selected-import",item:item,baseline:item.updatedAt))
        try await ItemDraftRepository(db:q).save(ItemDraft.make(id:"unrelated-editor",item:other,baseline:other.updatedAt))
        let untouched = try unwrap(try await ItemDraftRepository(db:q).get("unrelated-editor"))
        try await repo.placeImported(ids:[item.id],roomId:b.id,nodeId:nil)
        let moved = try unwrap(try await ItemRepository(db:q).getById(item.id)); eq(moved.locationId,b.id); eq(moved.updatedAt,item.updatedAt)
        let draft = try unwrap(try await ItemDraftRepository(db:q).get("selected-import")); eq(try draft.item().locationId,b.id)
        let after = try unwrap(try await ItemDraftRepository(db:q).get("unrelated-editor")); eq(after.dataJson,untouched.dataJson); eq(after.updatedAt,untouched.updatedAt)
        await fails { try await repo.placeImported(ids:[item.id,other.id],roomId:a.id,nodeId:nil) }
        eq(try await ItemRepository(db:q).getById(item.id)?.locationId,b.id)
    }

}
