import XCTest
@preconcurrency import GRDB
@testable import lolita

final class DetailParityRegressionTests: XCTestCase {
    private struct Fixture: Sendable {
        let first: Item
        let second: Item
        let location: Location
        let otherLocation: Location
        let coordinate: Coordinate
    }

    private nonisolated static func fixture(_ db: Database) throws -> Fixture {
        var brand = Brand(name: "测试品牌"); try brand.insert(db)
        var category = Category(name: "连衣裙"); try category.insert(db)
        var location = Location(name: "衣柜"); try location.insert(db)
        var other = Location(name: "衣架"); try other.insert(db)
        var coordinate = Coordinate(name: "测试套装", description: "保留描述"); try coordinate.insert(db)
        var first = Item(name: "测试裙子", brandId: brand.id, categoryId: category.id,
                         description: "保留描述", colors: ["白色"], season: "春,秋", size: "M",
                         sizeChartImageUrl: "size.jpg", imageUrls: ["first.jpg"], coordinateId: coordinate.id,
                         locationId: location.id, createdAt: 123)
        try first.insert(db)
        var second = Item(name: "测试上衣", brandId: brand.id, categoryId: category.id,
                          imageUrls: ["second.jpg"], createdAt: 456)
        try second.insert(db)
        return Fixture(first: first, second: second, location: location, otherLocation: other, coordinate: coordinate)
    }

    @MainActor
    func testLocationMembershipIsAtomicAndPreservesItemFields() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        let values = try await database.dbQueue.write { @Sendable db in try Self.fixture(db) }
        let viewModel = LocationDetailViewModel(locationId: values.location.id, db: database.dbQueue)
        await viewModel.load()
        XCTAssertEqual(viewModel.items.map(\.id), [values.first.id])
        try await viewModel.saveMembership([values.second.id])
        let stored = try await database.dbQueue.read { @Sendable db in
            (try XCTUnwrap(Item.fetchOne(db, key: values.first.id)), try XCTUnwrap(Item.fetchOne(db, key: values.second.id)))
        }
        XCTAssertNil(stored.0.locationId)
        XCTAssertEqual(stored.1.locationId, values.location.id)
        XCTAssertEqual(stored.0.description, values.first.description)
        XCTAssertEqual(stored.0.imageUrls, values.first.imageUrls)
        XCTAssertEqual(stored.0.sizeChartImageUrl, values.first.sizeChartImageUrl)
        XCTAssertEqual(stored.0.coordinateId, values.coordinate.id)
        XCTAssertEqual(stored.0.createdAt, 123)
        do {
            try await LocationDetailDataFactory.saveMembership(db: database.dbQueue, locationId: values.location.id,
                                                               originalIds: [values.second.id], selectedIds: [values.first.id, 99999])
            XCTFail("A missing item must reject the whole batch")
        } catch {}
        let locations = try await database.dbQueue.read { @Sendable db in
            (try Item.fetchOne(db, key: values.first.id)?.locationId, try Item.fetchOne(db, key: values.second.id)?.locationId)
        }
        XCTAssertNil(locations.0)
        XCTAssertEqual(locations.1, values.location.id)
    }

    @MainActor
    func testUnassignedLocationLoadsAndRejectsConcurrentPlacementWithoutPartialWrites() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        let values = try await database.dbQueue.write { @Sendable db in try Self.fixture(db) }
        let viewModel = LocationDetailViewModel(locationId: -1, db: database.dbQueue)
        await viewModel.load()
        XCTAssertTrue(viewModel.isUnassigned)
        XCTAssertEqual(viewModel.items.map(\.id), [values.second.id])
        do {
            try await viewModel.assign([values.first.id, values.second.id], to: values.otherLocation.id)
            XCTFail("Already placed items must reject the whole assignment")
        } catch {}
        let second = try await database.dbQueue.read { @Sendable db in try XCTUnwrap(Item.fetchOne(db, key: values.second.id)) }
        XCTAssertNil(second.locationId)
        XCTAssertEqual(second.imageUrls, values.second.imageUrls)
        try await viewModel.assign([values.second.id], to: values.otherLocation.id)
        XCTAssertTrue(viewModel.items.isEmpty)
    }

    @MainActor
    func testItemAndCoordinateDetailsLoadSizeChartRelationshipsAndPaymentSummary() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        let values = try await database.dbQueue.write { @Sendable db in
            let values = try Self.fixture(db)
            var price = Price(itemId: values.first.id, type: .depositBalance, totalPrice: 300, deposit: 100, balance: 200)
            try price.insert(db)
            var deposit = Payment(priceId: price.id, amount: 100, dueDate: 1000, isPaid: true, paidDate: 1000)
            try deposit.insert(db)
            var balance = Payment(priceId: price.id, amount: 200, dueDate: 2000)
            try balance.insert(db)
            return values
        }
        let item = ItemDetailViewModel(itemId: values.first.id, db: database.dbQueue)
        await item.load()
        XCTAssertNil(item.errorMessage)
        XCTAssertEqual(item.item?.sizeChartImageUrl, "size.jpg")
        XCTAssertEqual(item.coordinate?.id, values.coordinate.id)
        XCTAssertEqual(item.locationName, "衣柜")
        XCTAssertEqual(item.totalPrice, 300)
        XCTAssertEqual(item.paidAmount, 100)
        XCTAssertEqual(item.unpaidAmount, 200)
        let coordinate = CoordinateDetailViewModel(db: database.dbQueue)
        await coordinate.load(coordinateId: values.coordinate.id)
        XCTAssertEqual(coordinate.totalPrice, 300)
        XCTAssertEqual(coordinate.paidAmount, 100)
        XCTAssertEqual(coordinate.unpaidAmount, 200)
        try await coordinate.saveItems([values.second.id, values.first.id])
        XCTAssertEqual(coordinate.items.map(\.id), [values.second.id, values.first.id])
        let stored = try await database.dbQueue.read { @Sendable db in try XCTUnwrap(Item.fetchOne(db, key: values.first.id)) }
        XCTAssertEqual(stored.imageUrls, values.first.imageUrls)
        XCTAssertEqual(stored.sizeChartImageUrl, values.first.sizeChartImageUrl)
    }

    @MainActor
    func testRemovingOutfitAssociationKeepsClothingAndPhotos() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        let (values, log) = try await database.dbQueue.write { @Sendable db in
            let values = try Self.fixture(db)
            var log = OutfitLog(date: 1000, note: "保留笔记", imageUrls: ["outfit.jpg"], createdAt: 321)
            try log.insert(db)
            try OutfitItemCrossRef(outfitLogId: log.id, itemId: values.first.id).insert(db)
            try OutfitItemCrossRef(outfitLogId: log.id, itemId: values.second.id).insert(db)
            return (values, log)
        }
        let viewModel = OutfitLogDetailViewModel(db: database.dbQueue)
        await viewModel.load(logId: log.id)
        try await viewModel.removeItem(values.first.id)
        XCTAssertEqual(viewModel.items.map(\.id), [values.second.id])
        XCTAssertEqual(viewModel.log?.note, "保留笔记")
        XCTAssertEqual(viewModel.log?.imageUrls.values, ["outfit.jpg"])
        XCTAssertEqual(viewModel.log?.createdAt, 321)
        let stored = try await database.dbQueue.read { @Sendable db in try XCTUnwrap(Item.fetchOne(db, key: values.first.id)) }
        XCTAssertEqual(stored.imageUrls, values.first.imageUrls)
        XCTAssertEqual(stored.coordinateId, values.coordinate.id)
        XCTAssertEqual(stored.locationId, values.location.id)
    }
}
