#if os(iOS)
import XCTest

/// Runs only against the isolated, seeded simulator prepared by the regression script.
/// These tests tap the shipping UI; no in-app test switches or repository calls are used.
@MainActor
final class OrderLedgerUITests: XCTestCase {
    private lazy var app = XCUIApplication(bundleIdentifier: "com.lolita.ios")

    private func begin() {
        continueAfterFailure = false
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.buttons["新增服饰"].waitForExistence(timeout: 15), app.debugDescription)
    }
    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 8), app.debugDescription, file: file, line: line)
        for _ in 0..<7 {
            if element.isHittable { element.tap(); return }
            app.swipeUp()
        }
        XCTFail("控件不可点击：\(element)\n\(app.debugDescription)", file: file, line: line)
    }
    private func button(_ label: String) -> XCUIElement { app.buttons[label].firstMatch }
    private func back() { tap(app.navigationBars.buttons.element(boundBy: 0)) }
    private func replace(_ field: XCUIElement, with value: String) {
        tap(field)
        let old = field.value as? String ?? ""
        let count = old == field.placeholderValue ? 0 : old.count
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count + 2) + value)
    }
    private func assertText(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let element = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 8), app.debugDescription, file: file, line: line)
    }
    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = name + "-hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
    }
    private func openOrders(item: Int) {
        tap(button("item-\(item)"))
        tap(button("管理购买订单与账本"))
        XCTAssertTrue(app.navigationBars["购买订单"].waitForExistence(timeout: 8), app.debugDescription)
    }
    private func openOrder(_ id: Int) { tap(button("order-\(id)")) }
    private func confirm() { tap(button("确认")) }

    func test01PurchasePartialPaymentPlanEditOverpaymentAndDiscard() {
        begin(); openOrders(item: 101)
        tap(button("建立购买订单"))
        replace(app.textFields["应付总额（含邮费）"], with: "1000.50")
        replace(app.textFields["其中邮费"], with: "20")
        screenshot("01-order-form-real-keyboard")
        tap(button("保存订单"))
        XCTAssertTrue(app.navigationBars["购买订单"].waitForExistence(timeout: 8))
        let current = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'order-'")).firstMatch
        tap(current)
        assertText("尚未录入真实付款")
        screenshot("02-order-created-without-actual")
        tap(button("记录真实付款"))
        replace(app.textFields["金额"], with: "200.25")
        screenshot("03-partial-payment-real-keyboard")
        tap(button("保存"))
        XCTAssertTrue(app.navigationBars["订单与账本"].waitForExistence(timeout: 8))
        assertText("¥200.25")
        screenshot("04-partial-payment-saved")
        tap(button("编辑付款计划"))
        replace(app.textFields["应付总额（含邮费）"], with: "1200.50")
        tap(button("保存订单"))
        XCTAssertTrue(app.navigationBars["订单与账本"].waitForExistence(timeout: 8))
        assertText("¥1200.50"); assertText("¥200.25"); assertText("¥1000.25")
        screenshot("05-plan-edited-actual-preserved")
        tap(button("记录真实付款"))
        replace(app.textFields["金额"], with: "1001")
        tap(button("保存"))
        XCTAssertTrue(app.alerts["保存失败"].waitForExistence(timeout: 8))
        assertText("超过订单未付余额")
        screenshot("06-overpayment-rejected")
        tap(button("确定"))
        XCTAssertEqual(app.textFields["金额"].value as? String, "1001")
        back()
        screenshot("07-unsaved-input-confirmation")
        tap(button("放弃修改"))
        XCTAssertTrue(app.navigationBars["订单与账本"].waitForExistence(timeout: 8))
        assertText("¥200.25")
        screenshot("08-overpayment-not-recorded")
    }

    func test02AmbiguousHistoryReviewAndArchive() {
        begin(); openOrders(item: 104)
        openOrder(1041)
        assertText("历史账本")
        tap(button("选择为当前订单")); confirm()
        assertText("购买资料核对")
        screenshot("09-history-selected-needs-review")
        tap(button("确认为历史已购（不补造实付）")); confirm()
        assertText("已保留历史拥有证据")
        screenshot("10-historical-ownership-confirmed")
        tap(button("记录真实付款"))
        replace(app.textFields["金额"], with: "40")
        let unknownDate = app.switches["历史付款日期未知"]
        XCTAssertTrue(unknownDate.waitForExistence(timeout: 5))
        unknownDate.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(unknownDate.value as? String, "1", "必须真正开启未知日期，不能用真实日期通过测试")
        screenshot("11a-unknown-date-switch-enabled")
        tap(button("保存"))
        XCTAssertTrue(app.navigationBars["订单与账本"].waitForExistence(timeout: 8))
        assertText("真实付款日期未知"); assertText("¥40.00")
        screenshot("11-historical-payment-unknown-date")
        tap(button("归档当前订单")); confirm()
        assertText("选择为当前订单")
        screenshot("12-order-archived-ledger-retained")
        XCTAssertFalse(button("记录真实付款").exists)
    }

    func test03CreateSharedAccessoryAndPayOnlyThroughParent() {
        begin()
        tap(button("新增服饰"))
        replace(app.textFields["服饰名称（必填）"], with: "回归·共价小物")
        if app.keyboards.firstMatch.exists { app.swipeDown() }
        let parentPicker = button("parent-item-picker")
        for _ in 0..<5 {
            if parentPicker.exists && parentPicker.isHittable { break }
            app.swipeUp(velocity: .slow)
        }
        tap(parentPicker)
        tap(button("回归·主件"))
        // The new toggle is below the keyboard. Drag within the visible form;
        // virtualized offscreen Form rows can report a zero accessibility frame.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)))
        let included = app.switches["价格包含在主件订单中"]
        XCTAssertTrue(included.waitForExistence(timeout: 5))
        screenshot("12a-shared-toggle-before-tap")
        XCTAssertGreaterThan(included.frame.height, 0, app.debugDescription)
        XCTAssertTrue(included.isHittable)
        included.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(included.value as? String, "1")
        screenshot("13-shared-accessory-edit")
        tap(button("保存"))
        XCTAssertTrue(app.buttons["新增服饰"].waitForExistence(timeout: 8))
        let child = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "回归·共价小物")).firstMatch
        tap(child)
        tap(button("管理购买订单与账本"))
        assertText("共用主件订单")
        screenshot("14-shared-owner-order")
        openOrder(1021)
        tap(button("记录真实付款"))
        replace(app.textFields["金额"], with: "50")
        tap(button("保存"))
        XCTAssertTrue(app.navigationBars["订单与账本"].waitForExistence(timeout: 8))
        assertText("¥150.00")
        screenshot("15-shared-order-partial-payment")
    }

    func test04ColdRelaunchPreservesHistoricalUnknownDate() {
        begin(); openOrders(item: 103); openOrder(1031)
        assertText("历史拥有证据")
        screenshot("16-upgraded-owned-history")
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["新增服饰"].waitForExistence(timeout: 15))
        openOrders(item: 103); openOrder(1031)
        assertText("真实付款日期未知")
        screenshot("17-cold-relaunch-history-preserved")
    }
    func test05DarkAccessibilityTextAndRealKeyboardSave() {
        begin(); openOrders(item: 101)
        tap(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'order-'")).firstMatch)
        assertText("¥1200.50"); assertText("¥200.25")
        screenshot("18-system-dark-accessibility-order")
        let totalDisplay = app.staticTexts["order-value-订单应付（含邮费）"]
        let shippingDisplay = app.staticTexts["order-value-其中邮费"]
        XCTAssertTrue(totalDisplay.exists && shippingDisplay.exists, app.debugDescription)
        XCTAssertGreaterThan(totalDisplay.frame.height, 0)
        XCTAssertLessThanOrEqual(totalDisplay.frame.height, shippingDisplay.frame.height + 1, "订单金额不能因大字体被拆成两行")
        tap(button("编辑付款计划"))
        let total = app.textFields["应付总额（含邮费）"]
        replace(total, with: "1200.50")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "必须使用真实系统键盘")
        XCTAssertLessThanOrEqual(total.frame.maxY, app.keyboards.firstMatch.frame.minY + 1)
        let save = button("保存订单")
        XCTAssertTrue(save.isHittable)
        XCTAssertLessThanOrEqual(save.frame.maxY, app.keyboards.firstMatch.frame.minY + 1)
        screenshot("19-system-dark-accessibility-real-keyboard")
        tap(save)
        XCTAssertTrue(app.navigationBars["订单与账本"].waitForExistence(timeout: 8))
        assertText("¥1000.25")
        screenshot("20-system-dark-accessibility-saved")
    }

}
#endif
