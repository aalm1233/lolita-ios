import XCTest
import GRDB
import SwiftUI
import ImageIO
import CoreText
@testable import lolita

final class LookAndShareRegressionTests: XCTestCase {
    func testWholeLookUsesStableRolesOwnedItemsAndDeterministicReasons() {
        let categories = [Category(id: 1, name: "改名主裙", categorySemantic: .jsk), Category(id: 2, name: "改名头饰", categorySemantic: .kc), Category(id: 3, name: "自定义配件"), Category(id: 4, name: "OP", categorySemantic: .op)]
        let target = Item(id: 1, name: "主件", brandId: 1, categoryId: 1, colors: ["蓝"], season: "春，秋", style: "古典")
        let best = Item(id: 2, name: "呼应", brandId: 1, categoryId: 2, colors: ["蓝"], season: "秋,冬", style: "古典")
        let fallback = Item(id: 3, name: "另一件", brandId: 1, categoryId: 2)
        let custom = Item(id: 4, name: "手作", brandId: 1, categoryId: 3)
        let wish = Item(id: 5, name: "心愿", brandId: 1, categoryId: 2, status: .wished)
        let otherDress = Item(id: 6, name: "另主裙", brandId: 1, categoryId: 4)
        let groups = FullLookEngine.build(target: target, candidates: [fallback, best, best, wish, custom, otherDress, target], categories: categories, history: [2])
        XCTAssertEqual(groups.map(\.id), ["头饰", "自定义配件"])
        XCTAssertEqual(groups[0].options.map(\.item.id), [2, 3])
        XCTAssertEqual(groups[0].options[0].score, 6)
        XCTAssertEqual(groups[0].options[0].reasons, ["风格相同", "颜色呼应", "季节适合", "曾经一起搭配"])
        XCTAssertEqual(groups[1].options[0].reasons, ["补齐自定义配件，可自行替换"])
    }
    func testOPExcludesBlouseAndAllMainDressRoles() {
        let cats = [Category(id: 1, name: "已改名", categorySemantic: .op), Category(id: 2, name: "衬衣", categorySemantic: .blouse), Category(id: 3, name: "SK", categorySemantic: .sk), Category(id: 4, name: "袜", categorySemantic: .tights)]
        let target = Item(id: 1, name: "主件", brandId: 1, categoryId: 1)
        let groups = FullLookEngine.build(target: target, candidates: (2...4).map { Item(id: Int64($0), name: "单品", brandId: 1, categoryId: Int64($0)) }, categories: cats, history: [])
        XCTAssertEqual(groups.map(\.id), ["袜子"])
    }
    func testSeasonTokensNotSubstringAndFourSeasonMatches() {
        let cats = [Category(id: 1, name: "JSK", categorySemantic: .jsk), Category(id: 2, name: "KC", categorySemantic: .kc)]
        let target = Item(id: 1, name: "主件", brandId: 1, categoryId: 1, season: "初春")
        let groups = FullLookEngine.build(target: target, candidates: [Item(id: 2, name: "非完整词", brandId: 1, categoryId: 2, season: "春"), Item(id: 3, name: "四季", brandId: 1, categoryId: 2, season: "四季")], categories: cats, history: [])
        XCTAssertEqual(groups[0].options.map(\.item.id), [3, 2]); XCTAssertEqual(groups[0].options[0].score, 1); XCTAssertEqual(groups[0].options[1].score, 0)
    }
    func testLockedAndSkippedSlotsSurviveShuffleAndCanBeChosenAgain() {
        let groups = [LookGroup(id: "头饰", options: [2,3].map { LookOption(item: Item(id: Int64($0), name: "头饰", brandId: 1, categoryId: 1), score: 0, reasons: []) }), LookGroup(id: "袜子", options: [4,5].map { LookOption(item: Item(id: Int64($0), name: "袜子", brandId: 1, categoryId: 1), score: 0, reasons: []) })]
        var selection = LookSelection(groups: groups); selection.locked = ["头饰"]
        selection.next(groups: groups); XCTAssertEqual(selection.selected, ["头饰": 2, "袜子": 5])
        selection.selected["袜子"] = nil; selection.next(groups: groups); XCTAssertEqual(selection.selected, ["头饰": 2])
        selection.locked = []; selection.next(groups: groups); XCTAssertEqual(selection.selected, ["头饰": 3])
        selection.selected["袜子"] = 4; selection.next(groups: groups); XCTAssertEqual(selection.selected, ["头饰": 2, "袜子": 5])
    }
    private static func fixture() async throws -> (DatabaseQueue, [Item], Coordinate) {
        let q = try LolitaDatabase(path: ":memory:").dbQueue
        return try await q.write { db in
            var brand = Brand(name: "品牌"); try brand.insert(db)
            var dress = Category(name: "主件", categorySemantic: .jsk); try dress.insert(db)
            var kc = Category(name: "头饰", categorySemantic: .kc); try kc.insert(db)
            var old = Coordinate(name: "历史套装", description: "私密备注", imageUrls: ["original.jpg"], createdAt: 123, updatedAt: 124); try old.insert(db)
            var first = Item(name: "主件", brandId: brand.id, categoryId: dress.id, description: "保留资料", imageUrls: ["photo.jpg"], coordinateId: old.id, createdAt: 10, updatedAt: 11); try first.insert(db)
            var second = Item(name: "头饰", brandId: brand.id, categoryId: kc.id); try second.insert(db)
            var historical = OutfitLog(date: 1, note: "曾经", imageUrls: ["log.jpg"]); try historical.insert(db)
            try OutfitItemCrossRef(outfitLogId: historical.id, itemId: first.id).insert(db); try OutfitItemCrossRef(outfitLogId: historical.id, itemId: second.id).insert(db)
            return (q, [first, second], old)
        }
    }
    func testLoadUsesOutfitAndCoordinateHistoryOnSingleReadSnapshot() async throws {
        let (q, items, _) = try await Self.fixture()
        let (target, groups) = try await LookRepository(db: q).load(itemId: items[0].id)
        XCTAssertEqual(target.id, items[0].id); XCTAssertEqual(groups[0].options[0].reasons, ["曾经一起搭配"])
        try await q.write { db in try db.execute(sql: "UPDATE items SET status='WISHED' WHERE id=?", arguments: [items[0].id]) }
        do { _ = try await LookRepository(db: q).load(itemId: items[0].id); XCTFail("心愿不能作为主件") } catch { XCTAssertTrue(error is ValidationError) }
    }
    func testSaveMovesExactlyReviewedMembersAndKeepsOldSetPhotosAndHistory() async throws {
        let (q, items, old) = try await Self.fixture()
        let saved = try await LookRepository(db: q).save(name: " 新套装 ", reviewed: items)
        XCTAssertGreaterThan(saved.id, old.id); XCTAssertEqual(saved.name, "新套装")
        try await q.read { db in
            let original = try XCTUnwrap(Coordinate.fetchOne(db, key: old.id)); XCTAssertEqual(original.name, old.name); XCTAssertEqual(original.imageUrls, old.imageUrls); XCTAssertEqual(original.updatedAt, 124)
            let stored = try Item.order(Item.Columns.id).fetchAll(db)
            XCTAssertEqual(stored.map(\.coordinateId), [saved.id, saved.id]); XCTAssertEqual(stored.map(\.coordinateOrder), [0,1])
            XCTAssertEqual(stored[0].description, "保留资料"); XCTAssertEqual(stored[0].imageUrls.values, ["photo.jpg"]); XCTAssertEqual(stored[0].createdAt, 10)
            XCTAssertEqual(try OutfitItemCrossRef.fetchCount(db), 2); XCTAssertEqual(try OutfitLog.fetchOne(db)?.imageUrls.values, ["log.jpg"])
            XCTAssertEqual(try Price.fetchCount(db), 0); XCTAssertEqual(try Payment.fetchCount(db), 0)
        }
    }
    func testStaleMembershipRejectsWholeSaveWithoutMovingOtherItems() async throws {
        let (q, items, old) = try await Self.fixture(); let repo = LookRepository(db:q)
        try await q.write { db in try db.execute(sql: "UPDATE items SET coordinateId=NULL WHERE id=?", arguments: [items[0].id]) }
        do { _ = try await repo.save(name:"不应建立", reviewed:items); XCTFail() } catch { XCTAssertTrue(error is ValidationError) }
        try await q.read { db in XCTAssertEqual(try Coordinate.fetchCount(db),1); XCTAssertNil(try Item.fetchOne(db,key:items[1].id)?.coordinateId); XCTAssertNotNil(try Coordinate.fetchOne(db,key:old.id)) }
    }
    func testDeletedOrNoLongerOwnedMemberRollsBackAndDuplicateIdsRejected() async throws {
        let (q, items, _) = try await Self.fixture(); let repo = LookRepository(db:q)
        try await q.write { db in try db.execute(sql:"UPDATE items SET status='WISHED' WHERE id=?",arguments:[items[1].id]) }
        for selection in [items, [items[0], items[0]], []] {
            do { _ = try await repo.save(name:"无效选择",reviewed:selection); XCTFail() } catch { XCTAssertTrue(error is ValidationError) }
        }
        try await q.write { db in try db.execute(sql:"DELETE FROM outfitItemCrossRef WHERE itemId=?",arguments:[items[1].id]); try db.execute(sql:"DELETE FROM items WHERE id=?",arguments:[items[1].id]) }
        do { _ = try await repo.save(name:"已删除",reviewed:items); XCTFail() } catch { XCTAssertTrue(error is ValidationError) }
        let count = try await q.read { db in try Coordinate.fetchCount(db) }; XCTAssertEqual(count,1)
    }
    func testShareWhitelistBrandSwitchHeroLimitAndPagination() throws {
        let items = (1...13).map { Item(id:Int64($0),name:"服饰\($0)",brandId:1,categoryId:1,description:"秘密备注",imageUrls:["photo.jpg"],locationId:999,source:"秘密渠道") }
        let content = ShareCardContent(title:"套装",images:["1","2","3","4"],items:items,brands:[1:"公开品牌"],showBrands:false)
        XCTAssertEqual(content.pages.map(\.count),[6,6,1]); XCTAssertEqual(content.images,["1","2","3"])
        let json = String(decoding:try JSONEncoder().encode(content),as:UTF8.self)
        for secret in ["秘密", "locationId", "price", "status", "source", "公开品牌"] { XCTAssertFalse(json.contains(secret)) }
        XCTAssertTrue(json.contains("服饰13")); XCTAssertTrue(content.items.allSatisfy { $0.brand == nil })
        XCTAssertEqual(ShareCardContent(title:"套装",images:[],items:items,brands:[1:"公开品牌"],showBrands:true).items[0].brand,"公开品牌")
        XCTAssertEqual(ShareCardContent(title:"空套装",images:[],items:[],brands:[:],showBrands:true).pages.count,1)
    }
    private func validPNG() throws -> Data {
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        let context = try XCTUnwrap(CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.9, green: 0.2, blue: 0.3, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
    func testSavedLookRoundTripsJSONAndZIPWithOriginalSetAndImageBytes() async throws {
        let (q, items, old) = try await Self.fixture()
        let image = try validPNG(), path = try XCTUnwrap(ImageFileHelper.save(imageData: image))
        defer { ImageFileHelper.delete(path: path) }
        try await q.write { db in
            let json = String(decoding: try JSONEncoder().encode([path]), as: UTF8.self)
            for table in ["items", "coordinates", "outfitLogs"] { try db.execute(sql: "UPDATE \(table) SET imageUrls=?", arguments: [json]) }
        }
        let saved = try await LookRepository(db: q).save(name: "备份搭配", reviewed: items)
        let manager = BackupManager(db: q)
        let json = try await manager.exportJSON()
        let preview = try BackupManager.preview(json)
        XCTAssertTrue(preview.coordinates.contains { $0.id == old.id && $0.description == "私密备注" })
        let zip = try await manager.exportZIP(), url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        try zip.write(to: url); defer { try? FileManager.default.removeItem(at: url) }
        let prepared = try BackupManager.prepare(at: url)
        for mode in 0..<2 {
            let restored = try LolitaDatabase(path: ":memory:").dbQueue, target = BackupManager(db: restored)
            if mode == 0 { try await target.restore(preview) } else { try await target.restore(prepared) }
            let contents = try await target.snapshot()
            XCTAssertEqual(contents.coordinates.count, 2)
            XCTAssertTrue(contents.items.allSatisfy { $0.coordinateId == saved.id })
            XCTAssertEqual(contents.outfitItemCrossRefs.count, 2)
            for item in contents.items { let restoredPath = try XCTUnwrap(item.imageUrls.values.first); XCTAssertEqual(try Data(contentsOf: ImageFileHelper.fileURL(for: restoredPath)), image) }
        }
    }
    @MainActor
    func testShareRendersBoundedPNGsWithActualPhotoAndMissingPhotoFallbackWithoutChangingOriginal() async throws {
        let original = try validPNG(), path = try XCTUnwrap(ImageFileHelper.save(imageData:original))
        defer { ImageFileHelper.delete(path:path) }
        let items=(1...7).map { Item(id:Int64($0),name:String(repeating:"很长的名字",count:80),brandId:1,categoryId:1,imageUrls:[$0 == 1 ? path : "missing.jpg"]) }
        let files = try await ShareCardRenderer.render(ShareCardContent(title:"分享测试",images:[path],items:items,brands:[:],showBrands:false),skin:SweetSkin(),dark:false)
        defer { for file in files { try? FileManager.default.removeItem(at:file.deletingLastPathComponent()) } }
        XCTAssertEqual(files.count,2)
        for file in files { let src=try XCTUnwrap(CGImageSourceCreateWithURL(file as CFURL,nil)); let image=try XCTUnwrap(CGImageSourceCreateImageAtIndex(src,0,nil)); XCTAssertEqual(image.width,1080); XCTAssertLessThan(image.height,4000) }
        XCTAssertEqual(try Data(contentsOf:URL(fileURLWithPath:path)),original)
    }
    @MainActor
    func testViewModelKeepsSelectionOnRepeatedLoadAndDoesNotDuplicateSave() async throws {
        let (q,items,_) = try await Self.fixture(); let vm=LookBuilderViewModel(db:q)
        await vm.load(items[0].id); vm.choose("头饰",id:nil); await vm.load(items[0].id)
        XCTAssertNil(vm.selection.selected["头饰"])
        let failed=await vm.save(" "); XCTAssertFalse(failed); XCTAssertNotNil(vm.error); XCTAssertNotNil(vm.target)
        let success=await vm.save("单主件"); XCTAssertTrue(success); let duplicate=await vm.save("再保存"); XCTAssertFalse(duplicate)
        let count=try await q.read { db in try Coordinate.fetchCount(db) }; XCTAssertEqual(count,2)
    }
    @MainActor
    func testBundledSkinFontsResolveTheirRealPostScriptNames() {
        _ = SkinManager()
        for type in SkinType.allCases {
            if let name = SkinManager.create(type).fontName {
                XCTAssertEqual(CTFontCopyPostScriptName(CTFontCreateWithName(name as CFString, 17, nil)) as String, name, type.rawValue)
            }
        }
    }

}
