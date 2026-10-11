import XCTest
@preconcurrency import GRDB
import Combine
@testable import lolita

final class CollectionFilterRegressionTests: XCTestCase {
    private let categories = [Category(id: 1, name: "连衣裙", group: .clothing), Category(id: 2, name: "发饰", group: .accessory)]
    private var items: [Item] {
        [Item(id: 1, name: "花园连衣裙", brandId: 1, categoryId: 1, status: .owned, colors: ["粉色", "白色"], season: "夏季", style: "甜美", updatedAt: 100),
         Item(id: 2, name: "花园发带", brandId: 1, categoryId: 2, status: .pendingBalance, colors: ["白色"], season: "夏季", style: "甜美", updatedAt: 200),
         Item(id: 3, name: "花园心愿裙", brandId: 1, categoryId: 1, status: .wished, colors: ["白色"], season: "夏季", style: "甜美", updatedAt: 300),
         Item(id: 4, name: "黑色经典裙", brandId: 2, categoryId: 1, status: .owned, colors: ["黑色"], season: "冬季", style: "古典", updatedAt: 400)]
    }

    func testWardrobeIncludesPendingBalanceAndExcludesWishlistWhenFilteringCategoryGroup() {
        let filter = ItemCollectionFilter(group: .clothing)
        XCTAssertEqual(filter.apply(to: items, categories: categories, collection: .owned, newestFirst: true).map(\.id), [4, 1])
        XCTAssertEqual(ItemCollectionFilter(group: .accessory).apply(to: items, categories: categories, collection: .owned, newestFirst: true).map(\.id), [2])
        XCTAssertEqual(ItemCollectionFilter().apply(to: items, categories: categories, collection: .owned, newestFirst: true).map(\.id), [4, 2, 1])
    }

    func testAllPropertyFiltersIntersectAndColorMatchesAnyStoredColor() {
        var filter = ItemCollectionFilter(brandId: 1, categoryId: 1, group: .clothing, season: "夏季", style: "甜美", color: "白色", search: " 花园 ")
        XCTAssertEqual(filter.apply(to: items, categories: categories, collection: .owned, newestFirst: true).map(\.id), [1])
        filter.status = .pendingBalance
        XCTAssertTrue(filter.apply(to: items, categories: categories, collection: .owned, newestFirst: true).isEmpty)
        filter.categoryId = nil
        filter.group = .accessory
        XCTAssertEqual(filter.apply(to: items, categories: categories, collection: .owned, newestFirst: true).map(\.id), [2])
        filter.color = "粉色"
        XCTAssertTrue(filter.apply(to: items, categories: categories, collection: .owned, newestFirst: true).isEmpty)
    }

    func testWishlistFiltersNeverLeakOwnedOrPendingRecordsAndUnknownCategoriesDoNotMatchGroup() {
        XCTAssertEqual(ItemCollectionFilter(color: "白色").apply(to: items, categories: categories, collection: .wished, newestFirst: true).map(\.id), [3])
        let orphan = Item(id: 5, name: "旧分类服饰", brandId: 1, categoryId: 99)
        XCTAssertTrue(ItemCollectionFilter(group: .clothing).apply(to: [orphan], categories: categories, collection: .owned, newestFirst: true).isEmpty)
        XCTAssertEqual(ItemCollectionFilter().apply(to: [orphan], categories: categories, collection: .owned, newestFirst: true).map(\.id), [5])
    }

    func testCombinedSeasonValuesMatchEachSeasonAndIgnoreWhitespace() {
        let item = Item(id: 10, name: "多季服饰", brandId: 1, categoryId: 1, season: "春, 秋 , ,冬")
        for season in ["春", "秋", "冬"] {
            XCTAssertEqual(ItemCollectionFilter(season: season).apply(to: [item], categories: categories, collection: .owned, newestFirst: true).map(\.id), [10])
        }
        XCTAssertTrue(ItemCollectionFilter(season: "夏").apply(to: [item], categories: categories, collection: .owned, newestFirst: true).isEmpty)
        XCTAssertEqual(ItemCollectionFilter.seasons(in: item.season), ["春", "秋", "冬"])
    }

    func testPriceAndUpdateSortApplyToTheFilteredWardrobeAndHaveStableTies() {
        let filter = ItemCollectionFilter()
        let prices: [Int64: Double] = [1: 500, 2: 200, 3: 2000, 4: 700]
        XCTAssertEqual(filter.apply(to: items, categories: categories, collection: .owned, newestFirst: true, sort: .priceHighest, prices: prices).map(\.id), [4, 1, 2])
        XCTAssertEqual(filter.apply(to: items, categories: categories, collection: .owned, newestFirst: true, sort: .priceLowest, prices: prices).map(\.id), [2, 1, 4])
        XCTAssertEqual(filter.apply(to: items, categories: categories, collection: .owned, newestFirst: true, sort: .updatedOldest).map(\.id), [1, 2, 4])
        XCTAssertEqual(filter.apply(to: items.reversed(), categories: categories, collection: .owned, newestFirst: true, sort: .priceHighest, prices: [1: 10, 2: 10, 4: 10]).map(\.id), [1, 2, 4])
    }

    @MainActor
    func testCollectionObservationRefreshesPricesAndSharedOutfitItems() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        let values = try await database.dbQueue.write { db in
            var brand = Brand(name: "测试品牌"); try brand.insert(db)
            var category = Category(name: "测试分类"); try category.insert(db)
            var item = Item(name: "测试服饰", brandId: brand.id, categoryId: category.id, season: "春, 秋 ,冬"); try item.insert(db)
            var log = OutfitLog(date: Int64(Date().timeIntervalSince1970 * 1000), note: "观察回归"); try log.insert(db)
            try OutfitItemCrossRef(outfitLogId: log.id, itemId: item.id).insert(db)
            var first = Price(itemId: item.id, type: .full, totalPrice: 100); try first.insert(db)
            var second = Price(itemId: item.id, type: .full, totalPrice: 50); try second.insert(db)
            return (item.id, log.id)
        }
        let model = ItemListViewModel(db: database.dbQueue)
        defer { model.stopObserving() }
        let initial = expectation(description: "initial amounts")
        var initialToken: AnyCancellable? = model.$pricesByItem.sink { amounts in
            if amounts[values.0] == 150 { initial.fulfill() }
        }
        model.load()
        await fulfillment(of: [initial], timeout: 3)
        initialToken?.cancel(); initialToken = nil
        XCTAssertEqual(model.itemsByOutfit(values.1).map(\.id), [values.0])
        XCTAssertEqual(model.totalPrice(of: model.items), 150)
        XCTAssertEqual(Set(model.availableSeasons), Set(["春", "秋", "冬"]))

        let changed = expectation(description: "updated amounts")
        let changedToken = model.$pricesByItem.sink { amounts in
            if amounts[values.0] == 225 { changed.fulfill() }
        }
        defer { changedToken.cancel() }
        try await database.dbQueue.write { db in
            var price = Price(itemId: values.0, type: .full, totalPrice: 75); try price.insert(db)
        }
        await fulfillment(of: [changed], timeout: 3)
        XCTAssertEqual(model.totalPrice(of: model.items), 225)
    }
}
