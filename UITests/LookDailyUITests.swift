#if os(iOS)
import XCTest

/// Interacts with the shipping UI on a dedicated simulator containing fictional fixtures.
@MainActor
final class LookDailyUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier:"com.lolita.ios")
    private func begin() {
        continueAfterFailure=false
        app.launchArguments=["-AppleLanguages","(zh-Hans)","-AppleLocale","zh_CN"]
        app.launch();XCTAssertTrue(button("新增服饰").waitForExistence(timeout:20),app.debugDescription)
    }
    private func button(_ id:String)->XCUIElement { app.buttons[id].firstMatch }
    private func tap(_ element:XCUIElement,file:StaticString = #filePath,line:UInt = #line) {
        if !element.exists { _ = element.waitForExistence(timeout: 2) }
        for attempt in 0..<28 {
            let targetIdentifier = element.exists ? element.identifier : "missing"
            if element.exists && element.elementType == .searchField && element.frame.height > 0 && element.frame.minY >= 110 && element.frame.maxY < app.frame.height-100 {
                element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap(); return
            }
            let isNavigation=element.exists && element.elementType == .button && element.frame.minY < 115
            let bars=["look-save","quick-outfit-save","share-export"].map { button($0) }.first { $0.exists && $0.isHittable && $0.identifier != targetIdentifier }
            if element.exists && element.isHittable && element.isEnabled && element.frame.height>0 && (isNavigation || element.frame.minY>110) && (bars == nil || element.frame.maxY < bars!.frame.minY || element.identifier == "look-shuffle") {
                if element.elementType == .switch { element.coordinate(withNormalizedOffset:CGVector(dx:0.93,dy:0.5)).tap() } else { element.tap() };return
            }
            if app.keyboards.firstMatch.exists {
                let close = button("quick-dismiss-keyboard")
                if close.exists && close.isHittable { close.tap(); if targetIdentifier == "quick-dismiss-keyboard" { return }; continue }
                app.swipeDown(); if element.exists && element.isHittable { element.tap(); return }
            }
            let known=element.exists && element.frame.height>0
            let down=known ? element.frame.minY<130 : (attempt/6)%2==1
            app.coordinate(withNormalizedOffset:CGVector(dx:0.95,dy:down ? 0.25:0.68)).press(forDuration:0.05,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.95,dy:down ? 0.68:0.25)))
        }
        XCTFail("无法操作控件\n"+app.debugDescription,file:file,line:line)
    }
    private func text(_ value:String) { XCTAssertTrue(app.descendants(matching:.any).matching(NSPredicate(format:"label CONTAINS %@",value)).firstMatch.waitForExistence(timeout:12),app.debugDescription) }
    private func back() { tap(app.navigationBars.buttons.element(boundBy:0)) }
    private func shot(_ name:String) { let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a);let tree=XCTAttachment(string:app.debugDescription);tree.name=name+"-hierarchy";tree.lifetime = .keepAlways;add(tree) }
    private func openItem(_ id:Int) { tap(button("服饰"));tap(button("item-\(id)")) }
    private func openCoordinate(_ id:Int) { tap(button("套装"));tap(button("coordinate-\(id)")) }
    private func restart() { app.terminate();app.launch();XCTAssertTrue(button("新增服饰").waitForExistence(timeout:20)) }
    private func replace(_ field:XCUIElement,_ value:String) {
        tap(field);let old=field.value as? String ?? "";field.coordinate(withNormalizedOffset:CGVector(dx:0.95,dy:0.5)).tap()
        field.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:(old==field.placeholderValue ? 0:old.count)+2)+value)
        XCTAssertEqual(field.value as? String,value,app.debugDescription)
    }
    private func setMoney(_ visible:Bool) {
        tap(app.tabBars.buttons["个人"]);let toggle=app.switches["显示总价"].firstMatch
        tapToReveal(toggle)
        if (toggle.value as? String == "1") != visible { tap(toggle) }
        XCTAssertEqual(toggle.value as? String,visible ? "1":"0",app.debugDescription)
    }
    private func tapToReveal(_ element:XCUIElement) {
        for attempt in 0..<20 {
            if element.exists && element.isHittable && element.frame.minY > 115 && element.frame.maxY < app.frame.height-100 { return }
            let down=element.exists && element.frame.height>0 ? element.frame.minY < 115 : (attempt/6)%2==1
            if down { app.swipeDown() } else { app.swipeUp() }
        }
        XCTFail(app.debugDescription)
    }
    private func shareReady(_ label:String) { XCTAssertTrue(button("share-export").waitForExistence(timeout:30),app.debugDescription);let enabled=XCTNSPredicateExpectation(predicate:NSPredicate(format:"enabled == true AND label == %@",label),object:button("share-export"));XCTAssertEqual(XCTWaiter.wait(for:[enabled],timeout:35),.completed,app.debugDescription) }

    func test01LockShuffleReplaceSkipAndSaveReviewedMove() {
        begin();openItem(9001);tap(button("full-look"));text("整套搭配");text("回归·蓝色头饰")
        let lock=app.switches["look-lock-头饰"].firstMatch;tap(lock);XCTAssertEqual(lock.value as? String,"1")
        tap(button("look-shuffle"));text("回归·蓝色头饰");text("回归·红色袜子");shot("01-locked-head-survives-shuffle")
        tap(button("look-skip-袜子"));tap(button("look-shuffle"));text("已跳过")
        tap(button("look-replace-头饰"));let search=app.searchFields.firstMatch;tap(search);search.typeText("红色头饰");tap(button("look-option-9003"));text("回归·红色头饰");shot("02-search-replacement-and-skipped-socks")
        tap(button("look-save"));text("原套装和照片会保留");XCTAssertFalse(button("look-confirm").isEnabled)
        replace(app.textFields["look-name"],"回归·完成整套");shot("03-explicit-membership-move-confirmation")
        tap(button("look-confirm"));XCTAssertTrue(app.navigationBars["套装详情"].waitForExistence(timeout:15),app.debugDescription);text("回归·完成整套");shot("04-reviewed-set-saved")
        restart();openCoordinate(9001);text("回归·原套装");shot("05-old-set-and-original-photo-retained")
    }
    func test02MultiPageShareBrandToggleAndActualSystemShareSheet() {
        begin();openCoordinate(9002);tap(button("share-card"));shareReady("分享 3 张图片");shot("06-share-three-pages-with-brand")
        tap(app.switches["share-brands"].firstMatch);shareReady("分享 3 张图片");shot("07-share-brand-hidden-regenerated")
        tap(button("share-export"));text("拷贝");shot("08-actual-system-image-share-sheet")
        // Opening the system chooser is exercised; no external recipient is selected.
        app.swipeDown();app.swipeDown()
    }
    func test03OutfitShareExcludesNotesAndRetainsPhotos() {
        begin();tap(app.tabBars.buttons["穿搭"])
        tap(app.buttons.matching(NSPredicate(format:"label CONTAINS %@","回归·私密穿搭笔记")).firstMatch)
        tap(button("share-card"));shareReady("分享图片");shot("09-outfit-share-photo-preview")
        XCTAssertFalse(app.staticTexts["回归·私密穿搭笔记"].isHittable)
        tap(button("关闭"));text("回归·私密穿搭笔记")
    }
    func test04PrivacyHidesSetMoneyAndReviewShortcutButExplicitEditingExplainsAmount() {
        begin();setMoney(false);tap(app.tabBars.buttons["首页"])
        XCTAssertFalse(button("purchase-review-shortcut").exists);openCoordinate(9003);text("金额已隐藏");XCTAssertFalse(app.staticTexts["¥1,234.56"].exists);shot("10-private-coordinate-summary")
        restart();openItem(9001);tap(button("管理购买订单与账本"));tap(button("order-9001"));text("金额已隐藏")
        tap(button("编辑付款计划"));text("本页为金额编辑，会临时显示金额");shot("11-explicit-order-editor-privacy-notice")
        restart();setMoney(true)
    }
    func test05PurchaseReviewSharedAccessoryRoutesToParentWithoutChangingCash() {
        begin();setMoney(true);tap(app.tabBars.buttons["首页"]);tap(button("purchase-review-shortcut"));text("待核对购买资料")
        let search=app.searchFields.firstMatch;tap(search);search.typeText("回归·共价小物");text("实付日期待补");shot("12-shared-child-review-reason")
        tap(button("review-order-9010"));text("购买订单");tap(button("order-9001"));text("真实付款日期未知");shot("13-shared-review-parent-ledger")
    }
    func test06TodayCancelPhotoThenUpdateSameRecordWithRealKeyboardAndSelection() {
        begin();tap(button("位置"));tap(button("home-today-outfit"));text("今天已有记录")
        replace(app.textFields["quick-outfit-note"],"回归·取消输入");tap(button("quick-dismiss-keyboard"))
        tap(button("add-photos-穿搭照片"));let photos=app.images.matching(identifier:"PXGGridLayout-Info");XCTAssertTrue(photos.firstMatch.waitForExistence(timeout:20),app.debugDescription);photos.firstMatch.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap();tap(button("完成"));XCTAssertTrue(app.navigationBars["照片"].waitForNonExistence(timeout:15))
        shot("14-today-real-photo-picker-added")
        back();tap(button("放弃更改"));tap(button("home-today-outfit"));XCTAssertEqual(app.textFields["quick-outfit-note"].value as? String,"回归·今日原笔记")
        replace(app.textFields["quick-outfit-note"],"回归·今日交互更新");tap(button("quick-dismiss-keyboard"));tap(button("选择服饰"))
        let search=app.searchFields.firstMatch;tap(search);search.typeText("回归·衬衫");tap(app.buttons.matching(NSPredicate(format:"label CONTAINS %@","回归·衬衫")).firstMatch);tap(button("item-selection-done"));shot("15-today-updated-note-and-selection")
        tap(button("quick-outfit-save"));XCTAssertTrue(button("home-today-outfit").waitForExistence(timeout:12));restart();tap(button("位置"));tap(button("home-today-outfit"));text("今天已有记录")
        XCTAssertEqual(app.textFields["quick-outfit-note"].value as? String,"回归·今日交互更新");text("回归·衬衫");shot("16-today-same-record-after-cold-relaunch")
    }
    func test07DarkAccessibilityThemeLookAndShareControls() {
        begin();tap(app.tabBars.buttons["个人"]);tap(button("theme-settings"));tap(button("哥特暗黑"));back();tap(app.tabBars.buttons["首页"]);openItem(9001);tap(button("full-look"))
        tap(app.switches["look-lock-头饰"].firstMatch);tap(button("look-shuffle"));shot("17-dark-accessibility-locked-look")
        restart();openCoordinate(9002);tap(button("share-card"));shareReady("分享 3 张图片");shot("18-dark-accessibility-share-preview")
        tap(app.switches["share-brands"].firstMatch);shareReady("分享 3 张图片");shot("19-dark-accessibility-brand-toggle")
    }
}
#endif
