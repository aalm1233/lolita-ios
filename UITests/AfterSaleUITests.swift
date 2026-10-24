#if os(iOS)
import XCTest

@MainActor
final class AfterSaleUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.lolita.ios")
    private func begin() {
        continueAfterFailure = false
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.buttons["新增服饰"].waitForExistence(timeout: 15), app.debugDescription)
    }
    private func button(_ name: String) -> XCUIElement { app.buttons[name].firstMatch }
    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 8), app.debugDescription, file: file, line: line)
        for _ in 0..<12 {
            if element.isHittable && element.frame.height > 0 { element.tap(); return }
            // Keep the start inside the form even when a keyboard or save bar is visible.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
                .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.22)))
        }
        XCTFail("控件未能滚入可操作区域\n\(app.debugDescription)", file: file, line: line)
    }
    private func replace(_ name: String, _ value: String) {
        let field = app.textFields[name].firstMatch
        tap(field)
        let old = field.value as? String ?? ""
        let count = old == field.placeholderValue ? 0 : old.count
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count + 2) + value)
    }
    private func back() { tap(app.navigationBars.buttons.element(boundBy: 0)) }
    private func text(_ value: String) {
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", value)).firstMatch.waitForExistence(timeout: 8), app.debugDescription)
    }
    private func shot(_ name: String) {
        let s = XCTAttachment(screenshot: app.screenshot()); s.name = name; s.lifetime = .keepAlways; add(s)
        let h = XCTAttachment(string: app.debugDescription); h.name = name + "-hierarchy"; h.lifetime = .keepAlways; add(h)
    }
    private func openItem(_ id: Int, wish: Bool = false) {
        if wish { tap(button("心愿")) }
        tap(button("item-\(id)"))
    }
    private func openSale(_ id: Int = 102, wish: Bool = false) {
        openItem(id, wish: wish)
        tap(button("管理购买订单与账本"))
        tap(button("order-1021"))
        tap(button("after-sale"))
    }
    private func switchOn(_ name: String) {
        let value = app.switches[name]
        XCTAssertTrue(value.waitForExistence(timeout: 8))
        for _ in 0..<8 {
            if value.frame.height > 0 && value.isHittable { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
                .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.22)))
        }
        value.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(value.value as? String, "1")
    }
    private func openFinance() {
        tap(app.tabBars.buttons["个人"])
        tap(button("finance-overview"))
    }
    func test01ReferenceRestoresAfterRelaunchAndAdoptionDoesNotPurchase() {
        begin(); openItem(101, wish: true); tap(button("edit-reference"))
        replace("参考金额", "680.12")
        shot("01-reference-real-keyboard")
        app.terminate(); app.launch()
        XCTAssertTrue(button("新增服饰").waitForExistence(timeout: 15))
        openItem(101, wish: true); tap(button("edit-reference"))
        XCTAssertEqual(app.textFields["参考金额"].value as? String, "680.12")
        shot("02-reference-input-restored")
        print("RESTORED SAVE", button("finance-save").debugDescription)
        tap(button("finance-save"))
        shot("02b-restored-reference-after-save-tap")
        XCTAssertTrue(app.navigationBars["服饰详情"].waitForExistence(timeout: 8), app.debugDescription)
        text("¥680.12")
        tap(button("管理购买订单与账本")); text("尚未建立购买订单")
        tap(button("建立购买订单")); tap(button("采用独立参考价到草稿")); tap(button("采用参考价"))
        XCTAssertEqual(app.textFields["应付总额（含邮费）"].value as? String, "680.12")
        shot("03-reference-adopted-only-into-draft")
        back(); tap(button("放弃修改")); text("尚未建立购买订单")
        shot("04-reference-no-purchase")
    }
    func test02RefundRejectsExcessAndRestoresDraftThenSavesActualDifference() {
        begin(); openSale(); tap(button("record-refund"))
        let emptyAmount = app.textFields["到账金额"].value as? String ?? ""
        XCTAssertTrue(emptyAmount.isEmpty || emptyAmount == "到账金额", "到账退款必须从空金额开始")
        replace("到账金额", "101")
        tap(button("finance-save")); XCTAssertTrue(app.alerts["保存失败"].waitForExistence(timeout: 8)); text("超过尚未退回")
        shot("05-excess-refund-rejected-input-retained")
        tap(button("确定")); XCTAssertEqual(app.textFields["到账金额"].value as? String, "101")
        replace("到账金额", "25.25")
        tap(button("refund-kind")); tap(button("退差价"))
        shot("06-price-difference-draft-real-keyboard")
        app.terminate(); app.launch(); XCTAssertTrue(button("新增服饰").waitForExistence(timeout: 15))
        openSale(); tap(button("record-refund"))
        XCTAssertEqual(app.textFields["到账金额"].value as? String, "25.25")
        text("退差价"); tap(button("finance-save"))
        XCTAssertTrue(app.navigationBars["退款与取消购买"].waitForExistence(timeout: 8))
        text("¥25.25"); text("¥74.75")
        shot("07-refund-received-original-cash-preserved")
    }
    func test03CancelSharedPurchaseUnknownAgreementAndRepurchaseIndependently() {
        begin(); openSale(); tap(button("cancel-purchase"))
        XCTAssertEqual(app.switches["约定退款金额待确认"].value as? String, "1")
        switchOn("确认整笔取消及物品回到心愿")
        shot("08-explicit-entire-order-cancellation")
        tap(button("finance-save")); XCTAssertTrue(app.navigationBars["退款与取消购买"].waitForExistence(timeout: 8))
        text("已取消购买"); text("待确认")
        shot("09-cancelled-unknown-refund-agreement")
        app.terminate(); app.launch(); XCTAssertTrue(button("新增服饰").waitForExistence(timeout: 15))
        openItem(105, wish: true); text("心愿")
        shot("10-shared-child-returned-to-wish")
        tap(button("管理购买订单与账本")); text("共用主件订单")
        tap(button("建立购买订单")); replace("应付总额（含邮费）", "400"); tap(button("保存订单"))
        XCTAssertTrue(app.navigationBars["购买订单"].waitForExistence(timeout: 8))
        text("¥400.00"); text("已取消购买")
        shot("11-repurchase-new-current-old-ledger-retained")
    }
    func test04MonthlyNetBudgetAnnualViewAndDrilldown() {
        begin(); openFinance(); tap(button("设置月预算")); replace("预算金额", "1000")
        shot("12-budget-real-keyboard")
        tap(button("finance-save")); XCTAssertTrue(app.navigationBars["预算与资金"].waitForExistence(timeout: 8))
        text("¥-25.25"); text("¥1025.25")
        shot("13-cross-month-refund-negative-month-net")
        tap(button("年度付款")); text("1月"); text("到账退款")
        shot("14-annual-cash-and-pending-view")
        let number = Calendar.current.component(.month, from: Date())
        tap(button("查看\(number)月预算与明细")); text("¥1000.00")
        shot("15-annual-month-drilldown")
    }
    func test05DarkLargeTextActualKeyboardAndSave() {
        begin(); openFinance(); text("¥-25.25")
        shot("16-dark-system-accessibility-month-net")
        tap(button("设置月预算")); replace("预算金额", "1000")
        let field = app.textFields["预算金额"], keyboard = app.keyboards.firstMatch, save = button("finance-save")
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5), "必须使用系统真实键盘")
        XCTAssertGreaterThan(field.frame.height, 0)
        XCTAssertLessThanOrEqual(field.frame.maxY, keyboard.frame.minY + 1)
        XCTAssertTrue(save.isHittable)
        XCTAssertLessThanOrEqual(save.frame.maxY, keyboard.frame.minY + 1)
        shot("17-dark-large-text-real-keyboard-accessible-save")
        tap(save); XCTAssertTrue(app.navigationBars["预算与资金"].waitForExistence(timeout: 8))
        text("¥1025.25")
        shot("18-dark-large-text-saved")
    }
    func test06HiddenFinanceValuesDoNotLeakInReadonlyAccessibility() {
        begin(); tap(app.tabBars.buttons["个人"])
        let setting = app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", "显示总价")).firstMatch
        XCTAssertTrue(setting.waitForExistence(timeout: 8))
        for _ in 0..<8 { if setting.frame.height > 0 && setting.isHittable { break }; app.swipeUp() }
        setting.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(setting.value as? String, "0")
        // Return the settings scroll to the entry, which precedes the privacy setting.
        app.swipeDown(); app.swipeDown()
        tap(button("finance-overview")); text("金额已隐藏")
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "25.25")).firstMatch.exists)
        shot("19-readonly-finance-privacy")
        back()
        let restored = app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", "显示总价")).firstMatch
        for _ in 0..<8 { if restored.frame.height > 0 && restored.isHittable { break }; app.swipeUp() }
        restored.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap(); XCTAssertEqual(restored.value as? String, "1")
    }
    func test07DetailQuickPaymentCanSaveAndCorrectMistakenEntry() {
        begin(); openItem(102); tap(button("quick-record-payment"))
        replace("金额", "10")
        shot("20-detail-quick-payment-real-keyboard")
        tap(button("保存"))
        XCTAssertTrue(app.navigationBars["服饰详情"].waitForExistence(timeout: 8))
        tap(button("管理购买订单与账本"))
        tap(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'order-'")).firstMatch)
        text("¥10.00")
        shot("21-detail-quick-payment-saved")
        tap(button("删除误记")); tap(button("删除误记"))
        text("尚未录入真实付款")
        shot("22-mistaken-quick-payment-corrected")
    }
    func test08ExplicitZeroReferenceIsVisibleOnWishlistAndCanBeEdited() {
        begin(); openItem(101, wish: true); tap(button("edit-reference"))
        replace("参考金额", "0"); tap(button("finance-save"))
        XCTAssertTrue(app.navigationBars["服饰详情"].waitForExistence(timeout: 8)); text("¥0.00")
        back(); text("¥0.00")
        shot("23-explicit-zero-reference-visible-in-wishlist")
        tap(button("item-101")); tap(button("edit-reference"))
        replace("参考金额", "680.12"); tap(button("finance-save"))
        XCTAssertTrue(app.navigationBars["服饰详情"].waitForExistence(timeout: 8)); text("¥680.12")
    }

}
#endif
