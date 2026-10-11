import XCTest
import GRDB
@testable import lolita

final class StatsChartParityRegressionTests: XCTestCase {
    func testSectorHitTestingMatchesPositiveCumulativeSlices() {
        let rows = [StatsChartValue(name: "零值", amount: 0), StatsChartValue(name: "品牌A", amount: 30),
                    StatsChartValue(name: "品牌B", amount: 70), StatsChartValue(name: "无效", amount: .nan)]
        XCTAssertEqual(StatsChartSelection.sector(at: 0, rows: rows), "品牌A")
        XCTAssertEqual(StatsChartSelection.sector(at: 0.299, rows: rows), "品牌A")
        XCTAssertEqual(StatsChartSelection.sector(at: 0.3, rows: rows), "品牌B")
        XCTAssertEqual(StatsChartSelection.sector(at: 1, rows: rows), "品牌B")
        XCTAssertNil(StatsChartSelection.sector(at: -.infinity, rows: rows))
        XCTAssertNil(StatsChartSelection.sector(at: 1.01, rows: rows))
        XCTAssertNil(StatsChartSelection.sector(at: 0.5, rows: [StatsChartValue(name: "空", amount: 0)]))
    }

    func testDistributionGroupsBeyondTopTenAndPreservesDrilldownMembers() {
        let rows = (0..<12).map { StatsChartValue(name: "品牌\($0)", amount: Double($0)) }
        let grouped = StatsAggregates.groupedDistribution(rows)
        XCTAssertEqual(grouped.count, 11)
        XCTAssertEqual(grouped.last?.name, "其他")
        XCTAssertEqual(grouped.last?.amount, 21)
        XCTAssertEqual(grouped.last?.members, ["品牌10", "品牌11"])
        XCTAssertEqual(grouped.reduce(0) { $0 + $1.amount }, rows.reduce(0) { $0 + $1.amount })
        var collision = rows
        collision[0] = StatsChartValue(name: "其他", amount: 1)
        let collisionResult = StatsAggregates.groupedDistribution(collision)
        XCTAssertEqual(Set(collisionResult.map(\.id)).count, collisionResult.count)
    }

    func testOtherDistributionDrilldownIncludesEachMemberOnlyOnceWithinOwnedScope() {
        let items = [Item(id: 1, name: "已拥有A", brandId: 1, categoryId: 1, season: "春,秋"),
                     Item(id: 2, name: "已拥有B", brandId: 2, categoryId: 1, season: "夏"),
                     Item(id: 3, name: "心愿A", brandId: 1, categoryId: 1, status: .wished),
                     Item(id: 4, name: "尾款B", brandId: 2, categoryId: 1, status: .pendingBalance)]
        let brands = [Brand(id: 1, name: "A"), Brand(id: 2, name: "B")]
        let filter = StatsItemFilter.attributes("品牌", ["A", "B"], ownedOnly: true)
        XCTAssertEqual(Set(filter.apply(to: items, brands: brands, categories: [], prices: [], payments: []).map(\.id)), [1, 2])
        let seasons = StatsItemFilter.attributes("季节", ["春", "秋"], ownedOnly: true)
        XCTAssertEqual(seasons.apply(to: items, brands: brands, categories: [], prices: [], payments: []).map(\.id), [1])
    }

    func testWishlistFulfillmentUsesOwnedPlusWishedAndHandlesEmptyCollection() {
        XCTAssertEqual(StatsAggregates.fulfillmentRate(owned: 3, wished: 1), 0.75)
        XCTAssertEqual(StatsAggregates.fulfillmentRate(owned: 0, wished: 0), 0)
        XCTAssertEqual(StatsAggregates.fulfillmentRate(owned: 3, wished: 0), 1)
    }

    func testHiddenPriceFormattingAndChartDataRevealOnlyPercentages() {
        XCTAssertEqual(StatsDisplay.money(1234.56, visible: false), "¥***")
        XCTAssertEqual(StatsDisplay.money(1234.56, visible: true), "¥1234.56")
        XCTAssertEqual(StatsDisplay.chartAmount(100, total: 400, visible: false), 25)
        XCTAssertEqual(StatsDisplay.chartAmount(100, total: 400, visible: true), 100)
        XCTAssertEqual(StatsDisplay.chartAmount(0, total: 0, visible: false), 0)
        XCTAssertEqual(StatsDistributionChartStyle.allCases.map(\.rawValue), ["环图", "饼图", "柱状"])
        XCTAssertEqual(StatsTrendChartStyle.allCases.map(\.rawValue), ["折线", "柱状"])
    }

    @MainActor
    func testObservedWishlistRateExcludesPendingBalanceItems() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        try await database.dbQueue.write { @Sendable db in
            var brand = Brand(name: "品牌"); try brand.insert(db)
            var category = Category(name: "分类"); try category.insert(db)
            for status in [ItemStatus.owned, .owned, .owned, .wished, .pendingBalance, .pendingBalance] {
                var item = Item(name: status.rawValue, brandId: brand.id, categoryId: category.id, status: status)
                try item.insert(db)
            }
        }
        let vm = StatsPageViewModel(db: database.dbQueue)
        vm.load()
        defer { vm.stopObserving() }
        for _ in 0..<100 {
            if vm.items.count == 6 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(vm.ownedCount, 3)
        XCTAssertEqual(vm.wishedCount, 1)
        XCTAssertEqual(vm.pendingCount, 2)
        XCTAssertEqual(vm.wishlistFulfillmentRate, 0.75)
    }
}
