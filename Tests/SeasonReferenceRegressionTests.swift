import XCTest
import GRDB
@testable import lolita

final class SeasonReferenceRegressionTests: XCTestCase {
    private static func seed(_ db: Database) throws -> Season {
        var brand = Brand(name: "品牌"); try brand.insert(db)
        var category = Category(name: "分类"); try category.insert(db)
        var spring = Season(name: "春"); try spring.insert(db)
        for season in ["春, 秋", "春", "春季,秋"] {
            var item = Item(name: season, brandId: brand.id, categoryId: category.id, season: season)
            try item.insert(db)
        }
        return spring
    }

    func testRepositoryRenameAndDeleteRewriteOnlyExactSeasonTokens() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        var spring = try await database.dbQueue.write { @Sendable db in try Self.seed(db) }
        let repository = SeasonRepository(db: database.dbQueue)
        spring.name = "春日"
        try await repository.update(spring)
        var rows = try await database.dbQueue.read { @Sendable db in try Item.order(Item.Columns.id).fetchAll(db) }
        XCTAssertEqual(rows.map(\.season), ["春日,秋", "春日", "春季,秋"])
        try await repository.delete(spring)
        rows = try await database.dbQueue.read { @Sendable db in try Item.order(Item.Columns.id).fetchAll(db) }
        XCTAssertEqual(rows.map(\.season), ["秋", nil, "春季,秋"])
    }

    @MainActor
    func testAttributeManagerUpdatesCombinedSeasonReferencesInSameTransaction() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        let spring = try await database.dbQueue.write { @Sendable db in try Self.seed(db) }
        let vm = AttributeManageViewModel(db: database.dbQueue)
        let original = AttributeRow(id: spring.id, name: "春")
        try await vm.save(kind: .season, original: original, name: "春日", group: .clothing)
        try await vm.delete(kind: .season, row: AttributeRow(id: spring.id, name: "春日"))
        let rows = try await database.dbQueue.read { @Sendable db in try Item.order(Item.Columns.id).fetchAll(db) }
        XCTAssertEqual(rows.map(\.season), ["秋", nil, "春季,秋"])
        let count = try await database.dbQueue.read { @Sendable db in try Season.fetchCount(db) }
        XCTAssertEqual(count, 0)
    }

    @MainActor
    func testCommaInAttributeNameIsRejectedWithoutChangingStoredReferences() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        let spring = try await database.dbQueue.write { @Sendable db in try Self.seed(db) }
        let vm = AttributeManageViewModel(db: database.dbQueue)
        do {
            try await vm.save(kind: .season, original: AttributeRow(id: spring.id, name: spring.name), name: "春,夏", group: .clothing)
            XCTFail("一个季节不能写成多选字符串")
        } catch { XCTAssertTrue(error.localizedDescription.contains("逗号")) }
        let stored = try await database.dbQueue.read { @Sendable db in try Season.fetchOne(db, key: spring.id) }
        XCTAssertEqual(stored?.name, "春")
    }
}
