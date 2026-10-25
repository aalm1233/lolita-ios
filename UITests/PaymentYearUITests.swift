#if os(iOS)
import XCTest

@MainActor
final class PaymentYearUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.lolita.ios")
    private func button(_ id: String) -> XCUIElement { app.buttons[id].firstMatch }
    private func tap(_ element: XCUIElement) {
        for _ in 0..<12 {
            if element.exists && element.isHittable && (element.frame.midY < app.frame.height - 85 || element.label == "统计" || element.label == "个人") { element.tap(); return }
            app.swipeUp()
        }
        XCTFail(app.debugDescription)
    }
    private func begin() {
        continueAfterFailure = false
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(button("新增服饰").waitForExistence(timeout: 25), app.debugDescription)
        tap(app.tabBars.buttons["统计"])
        let tabs = app.scrollViews["compact-page-tabs"].firstMatch
        if !button("付款年历").isHittable { tabs.swipeLeft() }
        tap(button("付款年历"))
        XCTAssertTrue(button("payment-month-12").waitForExistence(timeout: 12), app.debugDescription)
    }
    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
        let t = XCTAttachment(string: app.debugDescription); t.name = name + "-tree"; t.lifetime = .keepAlways; add(t)
    }
    private func back() { tap(app.navigationBars.buttons.firstMatch) }
    func test01CompactGridMonthToggleYearAndBudget() {
        begin()
        for month in 1...12 { XCTAssertTrue(button("payment-month-\(month)").isHittable) }
        XCTAssertEqual(button("payment-month-1").frame.minY, button("payment-month-4").frame.minY, accuracy: 1)
        XCTAssertGreaterThan(button("payment-month-5").frame.minY, button("payment-month-1").frame.minY)
        XCTAssertTrue(button("payment-month-1").label.contains("100.00"), app.debugDescription)
        XCTAssertTrue(button("payment-month-2").label.contains("40.00"), app.debugDescription)
        tap(button("payment-month-1")); XCTAssertTrue(app.staticTexts["1月 付款记录"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["年历回归·分期裙"].exists)
        shot("year-grid-selected-january")
        tap(button("payment-month-1")); XCTAssertFalse(app.staticTexts["1月 付款记录"].exists)
        tap(button("payment-month-12")); XCTAssertTrue(app.staticTexts["当月无付款记录"].exists)
        tap(button("上一年")); XCTAssertFalse(app.staticTexts["12月 付款记录"].exists)
        tap(button("下一年")); tap(button("payment-month-2"))
        XCTAssertTrue(app.staticTexts["实付: \(Calendar.current.component(.year, from: Date()))-02-20"].waitForExistence(timeout: 5), app.debugDescription)
        shot("actual-paid-date-february")
        tap(button("payment-month-3")); XCTAssertTrue(app.staticTexts["年历回归·历史账本"].exists)
        tap(button("查看日期待定金额与预算")); XCTAssertTrue(app.navigationBars["预算与资金"].waitForExistence(timeout: 10))
        shot("undated-budget-entry"); back()
    }
    func test02RecordsRealPartialPaymentAndRefreshesAfterColdLaunch() {
        begin(); tap(button("payment-month-1")); tap(button("record-payment-95001"))
        XCTAssertTrue(app.navigationBars["记录真实付款"].waitForExistence(timeout: 10), app.debugDescription)
        let amount = app.textFields["金额"].firstMatch
        XCTAssertTrue(amount.waitForExistence(timeout: 10)); tap(amount); amount.typeText("25.25")
        shot("real-payment-form")
        tap(button("保存"))
        XCTAssertTrue(app.navigationBars["记录真实付款"].waitForNonExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(button("payment-month-1").label.contains("74.75"), app.debugDescription)
        shot("remaining-after-partial-payment")
        app.terminate(); begin()
        XCTAssertTrue(button("payment-month-1").label.contains("74.75"), app.debugDescription)
    }
    func test03BackgroundLongPressPickerAndMoneyPrivacy() {
        begin()
        let explanation = app.staticTexts["按实际付款日期统计已付，按应付日期统计待付。"].firstMatch
        explanation.press(forDuration: 5.2)
        XCTAssertTrue(button("查看背景").waitForExistence(timeout: 8), app.debugDescription)
        shot("five-second-background-actions"); tap(button("查看背景"))
        XCTAssertTrue(button("关闭照片").waitForExistence(timeout: 8), app.debugDescription)
        shot("preserved-shared-background-preview"); tap(button("关闭照片"))
        tap(button("设置日历背景")); tap(button("从相册选择"))
        XCTAssertTrue(app.navigationBars["照片"].waitForExistence(timeout: 12), app.debugDescription)
        shot("native-background-photo-picker"); tap(button("取消"))
        tap(button("设置日历背景")); tap(button("恢复默认"))
        tap(button("设置日历背景")); XCTAssertFalse(button("恢复默认").exists)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.6)).tap()
        tap(app.tabBars.buttons["个人"])
        tap(app.switches["显示总价"].firstMatch)
        tap(app.tabBars.buttons["统计"])
        XCTAssertTrue(app.staticTexts["金额已隐藏；记付款时将显示金额。"].waitForExistence(timeout: 10), app.debugDescription)
        tap(button("payment-month-1"))
        XCTAssertFalse(button("payment-month-1").label.contains("74.75"))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "¥")).firstMatch.exists, app.debugDescription)
        shot("hidden-money-calendar")
        tap(button("record-payment-95001")); XCTAssertTrue(app.navigationBars["记录真实付款"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["金额"].exists); back()
        tap(app.tabBars.buttons["个人"])
        // The settings scroll position is retained after returning from statistics.
        tap(app.switches["显示总价"].firstMatch)
    }
    func test05YearCalendarAcrossSevenSkins() {
        begin()
        for (index, theme) in ["甜美粉", "哥特暗黑", "中华风韵", "经典优雅", "清风水手", "田园牧歌", "维多利亚"].enumerated() {
            tap(app.tabBars.buttons["个人"]); tap(button("theme-settings")); tap(button(theme)); back()
            tap(app.tabBars.buttons["统计"])
            if !app.staticTexts["1月 付款记录"].exists { tap(button("payment-month-1")) }
            XCTAssertTrue(button("payment-month-12").exists)
            shot("skin-\(index)-\(theme)-year-calendar")
        }
        tap(app.tabBars.buttons["个人"]); tap(button("theme-settings")); tap(button("甜美粉")); back()
    }
    func test04DarkAccessibilityGridAndEmptyMonth() {
        begin(); tap(button("payment-month-12"))
        XCTAssertTrue(app.staticTexts["当月无付款记录"].waitForExistence(timeout: 8), app.debugDescription)
        shot("dark-accessibility-year-grid")
        tap(button("payment-month-1"))
        tap(button("record-payment-95001"))
        XCTAssertTrue(app.navigationBars["记录真实付款"].waitForExistence(timeout: 10), app.debugDescription)
        shot("dark-accessibility-payment-form"); back(); shot("dark-accessibility-records")
        tap(button("设置日历背景")); XCTAssertTrue(button("从相册选择").waitForExistence(timeout: 8))
        shot("dark-accessibility-background-menu")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.7)).tap()
    }
}
#endif
