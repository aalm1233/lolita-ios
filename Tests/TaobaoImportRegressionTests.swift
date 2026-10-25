import XCTest
import Foundation
import GRDB
import ZIPFoundation
@testable import lolita

final class TaobaoImportRegressionTests: XCTestCase {
    private static let header = ["订单号", "订单提交时间", "订单状态", "店铺名称", "商品名称", "商品链接", "型号款式", "商品数量", "商品金额", "实付金额", "运费"]

    static func xlsx(rows: [[String]], sharedStrings: Bool = false, numericDate: Bool = false, date1904: Bool = false, declaration: String = "") throws -> Data {
        let archive = try Archive(data: Data(), accessMode: .create)
        func escape(_ value: String) -> String { value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;") }
        let strings = rows.flatMap { $0 }
        var sharedIndex = 0
        let rowXML: String = rows.enumerated().map { rowIndex, row -> String in
            let cells = row.enumerated().map { column, value -> String in
                let reference = String(UnicodeScalar(65 + column)!) + String(rowIndex + 1)
                if numericDate, column == 1, rowIndex > 0 { sharedIndex += 1; return "<c r=\"\(reference)\"><v>\(escape(value))</v></c>" }
                if sharedStrings {
                    defer { sharedIndex += 1 }
                    return "<c r=\"\(reference)\" t=\"s\"><v>\(sharedIndex)</v></c>"
                }
                return "<c r=\"\(reference)\" t=\"inlineStr\"><is><t>\(escape(value))</t></is></c>"
            }.joined()
            return "<row r=\"\(rowIndex + 1)\">\(cells)</row>"
        }.joined()
        let files: [String: String] = [
            "xl/workbook.xml": "<workbook xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><workbookPr date1904=\"\(date1904 ? "1" : "0")\"/><sheets><sheet name=\"订单\" sheetId=\"7\" r:id=\"rId7\"/></sheets></workbook>",
            "xl/_rels/workbook.xml.rels": "<Relationships><Relationship Id=\"rId7\" Target=\"worksheets/sheet7.xml\"/></Relationships>",
            "xl/worksheets/sheet7.xml": declaration + "<worksheet><sheetData>\(rowXML)</sheetData></worksheet>",
            "xl/sharedStrings.xml": "<sst>\(strings.map { "<si><t>\(escape($0))</t></si>" }.joined())</sst>"
        ]
        for (path, value) in files {
            let data = Data(value.utf8)
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .deflate) { offset, size in
                data.subdata(in: Int(offset)..<min(data.count, Int(offset) + size))
            }
        }
        return try XCTUnwrap(archive.data)
    }

    private static func order(_ id: String = "12345678901234567890", name: String = "星辰 JSK", style: String = "蓝黑配色;Lady80;开襟OP", price: String = "￥1,200.50") -> [String] {
        [id, "2026-10-11 09:00", "交易成功", "测试品牌旗舰店", name, "https://item.taobao.com/item.htm?id=10", style, "1", price, price, "0"]
    }

    func testXLSXParsesSharedStringsFirstSheetMergedOrderRowsAndDeduplicatesFiles() throws {
        var second = Self.order(name: "小蝴蝶结", style: "白色;均码;KC", price: "50")
        for column in [0, 1, 2, 3, 9, 10] { second[column] = "" }
        let data = try Self.xlsx(rows: [Self.header, Self.order(), second], sharedStrings: true)
        let parsed = try TaobaoOrderParser.parseMultipleFiles([data, data])
        XCTAssertEqual(parsed.fileCount, 2)
        XCTAssertEqual(parsed.duplicateCount, 1)
        XCTAssertEqual(parsed.orders.count, 1)
        XCTAssertEqual(parsed.orders[0].orderId, "12345678901234567890")
        XCTAssertEqual(parsed.orders[0].items.count, 2)
        XCTAssertEqual(parsed.orders[0].items[0].price, 1200.5)
        XCTAssertEqual(parsed.orders[0].items[0].parsedType, "开襟OP")
        XCTAssertEqual(parsed.orders[0].items[0].parsedSize, "Lady80")
        XCTAssertEqual(parsed.orders[0].items[0].parsedColor, "蓝黑配色")
        XCTAssertEqual(parsed.orders[0].items[1].shopName, "测试品牌旗舰店")
        XCTAssertEqual(parsed.orders[0].items[1].id, "12345678901234567890:1")
    }

    func testInlineStringsExcelNumericDateAndSizePrefix() throws {
        var row = Self.order(style: "M半裙/粉色（定金不退）", price: "10")
        row[1] = "45000.5"
        let data = try Self.xlsx(rows: [Self.header, row], numericDate: true)
        let parsed = try TaobaoOrderParser.parse(data)
        XCTAssertEqual(parsed[0].orderTime, "2023-03-15 12:00:00")
        XCTAssertEqual(parsed[0].items[0].parsedType, "半裙")
        XCTAssertEqual(parsed[0].items[0].parsedSize, "M")
        XCTAssertEqual(parsed[0].items[0].parsedColor, "粉色")
        row[1] = "1"
        let date1904 = try TaobaoOrderParser.parse(Self.xlsx(rows: [Self.header, row], numericDate: true, date1904: true))
        XCTAssertEqual(date1904[0].orderTime, "1904-01-02 00:00:00")
    }

    func testMalformedHeadersNonFinitePricesAndXMLDeclarationsAreRejected() throws {
        XCTAssertThrowsError(try TaobaoOrderParser.parse(Self.xlsx(rows: [["随意标题"], Self.order()])))
        XCTAssertThrowsError(try TaobaoOrderParser.parse(Self.xlsx(rows: [Self.header, Self.order(price: "NaN")])))
        XCTAssertThrowsError(try TaobaoOrderParser.parse(Self.xlsx(rows: [Self.header, Self.order()], declaration: "<!DOCTYPE worksheet [<!ENTITY x SYSTEM 'file:///tmp/test'>]>")))
    }

    func testAutomaticPairingChecksVariantsAndLeavesAmbiguousMatchesForReview() throws {
        let rows = [Self.header, Self.order("1", name: "星辰（定金）", style: "蓝色;M;JSK", price: "100"), Self.order("2", name: "星辰（尾款）", style: "蓝色;M;JSK", price: "500"), Self.order("3", name: "星辰（尾款）", style: "红色;L;JSK", price: "500")]
        let items = try TaobaoOrderParser.orders(from: rows).flatMap(\.items)
        let paired = TaobaoImportMatching.autoPair(items.map(TaobaoImportDraft.init))
        XCTAssertEqual(paired[0].pairedWith, paired[1].id)
        XCTAssertEqual(paired[1].pairedWith, paired[0].id)
        XCTAssertNil(paired[2].pairedWith)
        let duplicateBalance = TaobaoImportDraft(original: try TaobaoOrderParser.orders(from: [Self.header, Self.order("4", name: "星辰（尾款）", style: "蓝色;M;JSK", price: "500")])[0].items[0])
        let ambiguous = TaobaoImportMatching.autoPair(items.map(TaobaoImportDraft.init) + [duplicateBalance])
        XCTAssertNil(ambiguous[0].pairedWith)
    }

    private static func fixture(_ db: Database) throws -> (Int64, Int64) {
        var brand = Brand(name: "测试品牌"); try brand.insert(db)
        var category = Category(name: "JSK"); try category.insert(db)
        return (brand.id, category.id)
    }

    private static func draft(id: String, name: String, price: String, brand: Int64, category: Int64) throws -> TaobaoImportDraft {
        let item = try TaobaoOrderParser.orders(from: [header, order(id, name: name, style: "蓝色;M;JSK", price: price)])[0].items[0]
        var draft = TaobaoImportDraft(original: item)
        draft.brandId = brand; draft.categoryId = category
        return draft
    }

    func testPairedPaymentsCommitAtomicallyAndRetryDeduplicatesPersistedKeys() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        let ids = try await database.dbQueue.write { @Sendable db in try Self.fixture(db) }
        var deposit = try Self.draft(id: "1", name: "星辰（定金）", price: "100", brand: ids.0, category: ids.1)
        var balance = try Self.draft(id: "2", name: "星辰（尾款）", price: "500", brand: 0, category: 0)
        deposit.pairedWith = balance.id; balance.pairedWith = deposit.id
        balance.purchaseDate = "2026-10-12 09:00"
        let repository = TaobaoImportRepository(db: database.dbQueue)
        let result = try await repository.save([deposit, balance])
        XCTAssertEqual(result.importedCount, 1); XCTAssertEqual(result.mergedCount, 1)
        let saved = try await database.dbQueue.read { @Sendable db in (try Item.fetchAll(db), try Price.fetchAll(db), try Payment.fetchAll(db)) }
        XCTAssertEqual(saved.0.count, 1); XCTAssertGreaterThan(saved.0[0].id, 0)
        XCTAssertEqual(saved.0[0].status, .owned)
        XCTAssertEqual(saved.0[0].importOrderKeys?.values, ["1:0", "2:0"])
        XCTAssertEqual(saved.1[0].totalPrice, 600); XCTAssertEqual(saved.1[0].type, .depositBalance)
        XCTAssertEqual(saved.2.map(\.amount).sorted(), [100, 500]); XCTAssertTrue(saved.2.allSatisfy(\.isPaid))
        XCTAssertNotEqual(saved.2[0].paidDate, saved.2[1].paidDate)
        try await database.dbQueue.write { @Sendable db in
            var item = try XCTUnwrap(Item.fetchOne(db, key: saved.0[0].id)); item.description = "用户编辑过描述"; try item.update(db)
        }
        let retry = try await repository.save([deposit, balance])
        XCTAssertEqual(retry.importedCount, 0); XCTAssertEqual(retry.duplicateCount, 2)
        let count = try await database.dbQueue.read { @Sendable db in try Item.fetchCount(db) }
        XCTAssertEqual(count, 1)
    }

    func testManualBalanceCreatesPendingStatusAndFailedBatchRollsBackEveryRow() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        let ids = try await database.dbQueue.write { @Sendable db in try Self.fixture(db) }
        let repository = TaobaoImportRepository(db: database.dbQueue)
        var deposit = try Self.draft(id: "1", name: "星辰定金", price: "100", brand: ids.0, category: ids.1)
        deposit.manualBalanceText = "400"
        deposit.balanceDueDate = Date(timeIntervalSince1970: 1800000000)
        var invalid = try Self.draft(id: "2", name: "另一件", price: "200", brand: ids.0, category: ids.1)
        invalid.purchaseDate = "不是日期"
        do { _ = try await repository.save([deposit, invalid]); XCTFail("无效日期必须失败") } catch {}
        let empty = try await database.dbQueue.read { @Sendable db in (try Item.fetchCount(db), try Price.fetchCount(db), try Payment.fetchCount(db)) }
        XCTAssertEqual(empty.0, 0); XCTAssertEqual(empty.1, 0); XCTAssertEqual(empty.2, 0)
        _ = try await repository.save([deposit])
        let saved = try await database.dbQueue.read { @Sendable db in (try Item.fetchAll(db), try Payment.fetchAll(db)) }
        XCTAssertEqual(saved.0[0].status, .pendingBalance)
        XCTAssertEqual(saved.1.filter { !$0.isPaid }.first?.amount, 400)
        XCTAssertEqual(saved.1.filter { !$0.isPaid }.first?.dueDate, 1800000000000)
    }

    func testBalanceFirstPairKeepsDepositMetadataAndUsesAddedBalancePhoto() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        let ids = try await database.dbQueue.write { @Sendable db in try Self.fixture(db) }
        var deposit = try Self.draft(id: "1", name: "星辰定金", price: "100", brand: ids.0, category: ids.1)
        var balance = try Self.draft(id: "2", name: "星辰尾款", price: "500", brand: 0, category: 0)
        deposit.pairedWith = balance.id; balance.pairedWith = deposit.id
        balance.imagePath = "/example/images/补图.jpg"
        _ = try await TaobaoImportRepository(db: database.dbQueue).save([balance, deposit])
        let saved = try await database.dbQueue.read { @Sendable db in try XCTUnwrap(Item.fetchAll(db).first) }
        XCTAssertEqual(saved.name, deposit.name)
        XCTAssertEqual(saved.brandId, deposit.brandId)
        XCTAssertEqual(saved.imageUrls.values, ["/example/images/补图.jpg"])
        XCTAssertEqual(Set(saved.importOrderKeys?.values ?? []), Set([deposit.id, balance.id]))
    }

    @MainActor
    func testFailureKeepsViewModelInputAndPairedInclusionChangesTogether() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        let ids = try await database.dbQueue.write { @Sendable db in try Self.fixture(db) }
        let vm = TaobaoImportViewModel(db: database.dbQueue)
        var deposit = try Self.draft(id: "1", name: "星辰定金", price: "100", brand: ids.0, category: ids.1)
        var balance = try Self.draft(id: "2", name: "星辰尾款", price: "500", brand: ids.0, category: ids.1)
        deposit.pairedWith = balance.id; balance.pairedWith = deposit.id
        vm.drafts = [deposit, balance]
        vm.setIncluded(false, for: deposit.id)
        XCTAssertFalse(vm.drafts[0].included); XCTAssertFalse(vm.drafts[1].included)
        vm.setIncluded(true, for: balance.id)
        vm.drafts[0].name = ""
        await vm.executeImport()
        XCTAssertNotNil(vm.error); XCTAssertEqual(vm.drafts[0].name, ""); XCTAssertFalse(vm.isWorking)
        let count = try await database.dbQueue.read { @Sendable db in try Item.fetchCount(db) }
        XCTAssertEqual(count, 0)
    }
    @MainActor func testPartialFileReadPersistsUsefulFileAndIndividualFailureAcrossViewModels() async throws {
        let q = try LolitaDatabase(path:":memory:").dbQueue
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true); defer { try? FileManager.default.removeItem(at:directory) }
        let good = directory.appendingPathComponent("valid.xlsx"), bad = directory.appendingPathComponent("broken.xlsx")
        let data = try Self.xlsx(rows:[Self.header,Self.order()]); try data.write(to:good); try Data([1,2,3]).write(to:bad)
        let model = TaobaoImportViewModel(db:q); await model.loadAttributes(); await model.loadFiles([good,bad])
        XCTAssertNil(model.error); XCTAssertEqual(model.orders.count,1); XCTAssertEqual(model.files.count,2)
        XCTAssertEqual(model.files.filter { $0.problem != nil }.count,1); XCTAssertEqual(model.files.first?.sha256,OrderImportSource.fileHash(data))
        let session = try XCTUnwrap(model.session)
        try FileManager.default.removeItem(at:good); try FileManager.default.removeItem(at:bad)
        let restored = TaobaoImportViewModel(db:q); await restored.loadAttributes(); await restored.restore(session.id)
        XCTAssertEqual(restored.files.count,2); XCTAssertEqual(restored.orders.count,1); XCTAssertEqual(restored.selectedKeys.count,1)
    }

}
