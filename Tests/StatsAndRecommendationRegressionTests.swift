import XCTest
import GRDB
@testable import lolita

final class StatsAndRecommendationRegressionTests: XCTestCase {
    func testMonthlyDrilldownUsesActualPaidMonthAndExcludesUnknownDates() {
        let items = [Item(id: 1, name: "已拥有", brandId: 1, categoryId: 1),
                     Item(id: 2, name: "尾款", brandId: 1, categoryId: 1, status: .pendingBalance),
                     Item(id: 3, name: "心愿", brandId: 1, categoryId: 1, status: .wished)]
        let prices = items.map { Price(id: $0.id, itemId: $0.id, type: .full, totalPrice: 100) }
        let october = Int64(1_759_276_800_000) // 2025-10-01T00:00Z
        let november = Int64(1_761_955_200_000)
        let payments = [Payment(id: 1, priceId: 1, amount: 50, dueDate: october, isPaid: true, paidDate: november),
                        Payment(id: 2, priceId: 1, amount: 50, dueDate: october, isPaid: true),
                        Payment(id: 3, priceId: 2, amount: 100, dueDate: october, isPaid: false),
                        Payment(id: 4, priceId: 3, amount: 100, dueDate: october, isPaid: true)]
        let result = StatsItemFilter.paymentPeriod("2025-10").apply(to: items, brands: [], categories: [], prices: prices, payments: payments)
        XCTAssertTrue(result.isEmpty, "不能用到期日补造真实付款月份")
        XCTAssertEqual(StatsItemFilter.paymentPeriod("2025-11").apply(to: items, brands: [], categories: [], prices: prices, payments: payments).map(\.id), [1])
        XCTAssertEqual(StatsItemFilter.paymentPeriod("2025-Q4").apply(to: items, brands: [], categories: [], prices: prices, payments: payments).map(\.id), [1])
    }

    func testStatusPriorityAndDistributionDrilldownsMatchTheirScope() {
        let items = [Item(id: 1, name: "已拥有", brandId: 1, categoryId: 1, season: "春,秋", style: "古典"),
                     Item(id: 2, name: "尾款", brandId: 1, categoryId: 1, status: .pendingBalance, season: "春,秋", style: "古典"),
                     Item(id: 3, name: "心愿", brandId: 1, categoryId: 1, status: .wished, priority: .high, season: "春,秋", style: "古典")]
        let brands = [Brand(id: 1, name: "品牌")]
        let categories = [Category(id: 1, name: "连衣裙")]
        func ids(_ filter: StatsItemFilter) -> Set<Int64> {
            Set(filter.apply(to: items, brands: brands, categories: categories, prices: [], payments: []).map(\.id))
        }
        XCTAssertEqual(ids(.status(.pendingBalance)), [2])
        XCTAssertEqual(ids(.priority(.high)), [3])
        XCTAssertEqual(ids(.attribute("品牌", "品牌", ownedOnly: true)), [1])
        XCTAssertEqual(ids(.attribute("分类", "连衣裙", ownedOnly: true)), [1])
        XCTAssertEqual(ids(.attribute("季节", "春", ownedOnly: true)), [1])
        XCTAssertEqual(ids(.attribute("季节", "秋", ownedOnly: true)), [1])
        XCTAssertEqual(ids(.attribute("风格", "古典", ownedOnly: false)), [1, 2, 3])
    }

    func testSeasonSpendingCountsMultiSeasonItemsInEachSelectedSeason() {
        let rows = StatsAggregates.seasonSpending([StyleSpending(style: "春, 秋", totalSpending: 200), StyleSpending(style: "春", totalSpending: 100)])
        let amounts = Dictionary(uniqueKeysWithValues: rows.map { ($0.style, $0.totalSpending) })
        XCTAssertEqual(amounts, ["春": 300, "秋": 200])
        let uncategorized = [Item(id: 1, name: "旧服饰", brandId: 1, categoryId: 1, style: ""), Item(id: 2, name: "新服饰", brandId: 1, categoryId: 1)]
        XCTAssertEqual(Set(StatsItemFilter.attribute("风格", "未分类", ownedOnly: false).apply(to: uncategorized, brands: [], categories: [], prices: [], payments: []).map(\.id)), [1, 2])
    }

    @MainActor
    func testStatsCatalogObservesPaymentChangesAndCancels() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        let vm = StatsPageViewModel(db: database.dbQueue)
        vm.load()
        defer { vm.stopObserving() }
        try await database.dbQueue.write { @Sendable db in
            var brand = Brand(name: "品牌"); try brand.insert(db)
            var category = Category(name: "分类"); try category.insert(db)
            var item = Item(name: "测试", brandId: brand.id, categoryId: category.id); try item.insert(db)
            var price = Price(itemId: item.id, type: .full, totalPrice: 200); try price.insert(db)
            var payment = Payment(priceId: price.id, amount: 200, dueDate: 0); try payment.insert(db)
        }
        for _ in 0..<100 {
            if vm.payments.count == 1 && vm.items.count == 1 && vm.categories.count == 1 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(vm.pricesByItem.values.reduce(0, +), 200)
        XCTAssertEqual(vm.filteredItems(.paymentPeriod("1970-01")).count, 0)
        try await database.dbQueue.write { @Sendable db in try db.execute(sql: "UPDATE payments SET isPaid=1, paidDate=0") }
        for _ in 0..<100 {
            if vm.filteredItems(.paymentPeriod("1970-01")).count == 1 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(vm.filteredItems(.paymentPeriod("1970-01")).count, 1)
        vm.stopObserving()
        try await database.dbQueue.write { @Sendable db in try db.execute(sql: "UPDATE payments SET isPaid=0") }
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(vm.payments.first?.isPaid == true)
        XCTAssertEqual(vm.trendSpending(year: "2026", quarters: false).count, 12)
        XCTAssertEqual(vm.trendSpending(year: "2026", quarters: true).count, 4)
        XCTAssertTrue(vm.trendSpending(year: "2026", quarters: false).allSatisfy { $0.totalSpending == 0 })
    }

    @MainActor
    func testCalendarMarkPaidUpdatesDerivedStatusAndKeepsPaidDateOnRepeat() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        let item = try await database.dbQueue.write { @Sendable db in
            var brand = Brand(name: "品牌"); try brand.insert(db)
            var category = Category(name: "分类"); try category.insert(db)
            var item = Item(name: "待付款", brandId: brand.id, categoryId: category.id); try item.insert(db)
            return item
        }
        let price = try await PriceRepository(db: database.dbQueue).saveWithPayments(Price(itemId: item.id, type: .full, totalPrice: 200))
        let repository = PaymentRepository(db: database.dbQueue)
        let vm = PaymentCalendarViewModel(repository: repository)
        let stage = try await database.dbQueue.read { @Sendable db in try XCTUnwrap(PaymentStage.fetchOne(db)) }
        let row = PaymentWithItemInfo(paymentId: -stage.id, amount: 200, dueDate: 0, isPaid: false,
                                      priceId: price.id, priceType: "FULL", itemName: item.name, itemId: item.id)
        try await vm.markPaid(row)
        let first = try await database.dbQueue.read { @Sendable db in try Payment.fetchOne(db) }
        XCTAssertTrue(first?.isPaid == true)
        XCTAssertNotNil(first?.paidDate)
        let savedStatus = try await database.dbQueue.read { @Sendable db in try Item.fetchOne(db, key: item.id)?.status }
        XCTAssertEqual(savedStatus, .owned)
        try await vm.markPaid(row)
        let repeated = try await database.dbQueue.read { @Sendable db in try Payment.fetchOne(db) }
        XCTAssertEqual(repeated?.paidDate, first?.paidDate)
    }

    func testRecommendationExcludesSameGroupAndBoostsCoordinateCompanions() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        let target = try await database.dbQueue.write { @Sendable db in
            var brand = Brand(name: "品牌"); try brand.insert(db)
            var clothing = Category(name: "服装", group: .clothing); try clothing.insert(db)
            var accessory = Category(name: "小物", group: .accessory); try accessory.insert(db)
            var coordinate = Coordinate(name: "套装", description: ""); try coordinate.insert(db)
            var target = Item(name: "裙子", brandId: brand.id, categoryId: clothing.id, colors: ["白色"], style: "古典", coordinateId: coordinate.id); try target.insert(db)
            var sameGroup = Item(name: "另一条裙子", brandId: brand.id, categoryId: clothing.id, colors: ["白色"], style: "古典"); try sameGroup.insert(db)
            var standalone = Item(name: "独立头饰", brandId: brand.id, categoryId: accessory.id, colors: ["白色"], style: "古典"); try standalone.insert(db)
            var companion = Item(name: "套装头饰", brandId: brand.id, categoryId: accessory.id, colors: ["白色"], style: "古典", coordinateId: coordinate.id); try companion.insert(db)
            var wished = Item(name: "心愿头饰", brandId: brand.id, categoryId: accessory.id, status: .wished, colors: ["白色"], style: "古典"); try wished.insert(db)
            return target
        }
        let scores = try await RecommendationRepository(db: database.dbQueue).getRecommendations(for: target, topN: Int.max)
        XCTAssertEqual(scores.map { $0.item.name }, ["套装头饰", "独立头饰"])
        XCTAssertEqual(scores[0].score / scores[1].score, 1.3, accuracy: 0.00001)
    }
}
