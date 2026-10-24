#if os(iOS)
import XCTest

@MainActor
final class WardrobeUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.lolita.ios")
    private func begin() {
        continueAfterFailure = false
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.buttons["新增服饰"].waitForExistence(timeout:15),app.debugDescription)
    }
    private func button(_ id: String) -> XCUIElement { app.buttons[id].firstMatch }
    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        if !element.exists { _ = element.waitForExistence(timeout:2) }
        for _ in 0..<16 {
            if element.exists {
                let bars = ["registration-save", "storage-save", "storage-members-save", "storage-move-save"].map { app.buttons[$0].firstMatch }
                let bar = bars.first { $0.exists && $0.isHittable && $0.identifier != element.identifier }
                let clearOfSaveBar = bar.map { element.frame.maxY < $0.frame.minY } ?? true
                let clearOfNavigationBar = element.elementType == .button || element.frame.minY >= 112
                if element.isHittable && element.isEnabled && element.frame.height > 0 && clearOfSaveBar && clearOfNavigationBar { element.tap(); return }
            }
            let closeKeyboard = app.buttons["dismiss-registration-keyboard"].firstMatch
            if app.keyboards.firstMatch.exists && closeKeyboard.exists && closeKeyboard.isHittable {
                closeKeyboard.tap()
                continue
            }
            if !element.exists || element.frame.height == 0 || element.frame.minY > app.frame.maxY {
                app.swipeUp(velocity:.fast)
                continue
            }
            let save = app.buttons["registration-save"].firstMatch
            var bottom = app.frame.height * 0.82
            if app.keyboards.firstMatch.exists { bottom = min(bottom,app.keyboards.firstMatch.frame.minY) }
            if save.exists && save.isHittable { bottom = min(bottom,save.frame.minY) }
            let known = element.exists && element.frame.height > 0
            let targetY = known ? element.frame.midY : bottom + 200
            let upwards = targetY > 140
            let distance = known ? min(120,abs(targetY-(112+bottom)/2)) : 220
            let fromY = upwards ? bottom-40 : 150
            let toY = upwards ? max(140,fromY-distance) : min(bottom-40,fromY+distance)
            let start = app.coordinate(withNormalizedOffset:CGVector(dx:0.95,dy:fromY/app.frame.height))
            let end = app.coordinate(withNormalizedOffset:CGVector(dx:0.95,dy:toY/app.frame.height))
            start.press(forDuration:0.05,thenDragTo:end,withVelocity:.slow,thenHoldForDuration:0.2)

        }
        XCTFail("无法操作控件\n"+app.debugDescription,file:file,line:line)
    }
    private func replace(_ field: XCUIElement, _ value: String) {
        tap(field); let old = field.value as? String ?? ""
        if !old.isEmpty && old != field.placeholderValue {
            tap(field)
            field.coordinate(withNormalizedOffset:CGVector(dx:0.99,dy:0.5)).tap()
        }
        field.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:(old == field.placeholderValue ? 0 : old.count)+2)+value)
        XCTAssertEqual(field.value as? String,value,"替换输入必须完整清除旧内容")
    }
    private func back() { tap(app.navigationBars.buttons.element(boundBy:0)) }
    private func shot(_ name: String) {
        let image=XCTAttachment(screenshot:app.screenshot()); image.name=name; image.lifetime = .keepAlways; add(image)
        let tree=XCTAttachment(string:app.debugDescription); tree.name=name+"-hierarchy"; tree.lifetime = .keepAlways; add(tree)
    }
    private func edit(_ id: Int) { tap(button("item-\(id)")); tap(button("编辑服饰")) }
    private func text(_ value: String) {
        XCTAssertTrue(app.descendants(matching:.any).matching(NSPredicate(format:"label CONTAINS %@",value)).firstMatch.waitForExistence(timeout:8),app.debugDescription)
    }
    private func room(_ id: Int) { tap(button("位置")); tap(button("location-\(id)")); tap(button("manage-storage")) }
    private func returnToList() { app.terminate(); app.launch(); XCTAssertTrue(button("新增服饰").waitForExistence(timeout:15)) }
    private func choosePhotos(_ title: String) {
        tap(button("add-photos-"+title))
        let loading=app.staticTexts["正在载入…"].firstMatch
        _ = XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == false"),object:loading)],timeout:30)
        shot("photo-library-"+title)
        // Actual system photo-library cells; no test-only application image injection.
        let photos=app.images.matching(identifier:"PXGGridLayout-Info")
        XCTAssertTrue(photos.element(boundBy:0).waitForExistence(timeout:20),app.debugDescription)
        XCTAssertGreaterThanOrEqual(photos.count,2,app.debugDescription)
        for index in 0..<2 {
            let photo = photos.element(boundBy:index)
            XCTAssertGreaterThan(photo.frame.height,0)
            XCTAssertTrue(app.frame.contains(CGPoint(x:photo.frame.midX,y:photo.frame.midY)))
            photo.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap()
        }
        let done = button("完成")
        XCTAssertTrue(done.isEnabled,app.debugDescription)
        done.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap()
        _ = XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == false"),object:app.navigationBars["照片"])],timeout:15)
        XCTAssertTrue(button("registration-save").waitForExistence(timeout:10))
    }
    func test01RegistrationDraftSurvivesExplicitExitAndRelaunchThenSavesSpecifications() {
        begin(); edit(101)
        replace(app.textFields["registration-name"],"回归·登记完成")
        tap(button("registration-category")); tap(button("鞋子"))
        replace(app.textFields["registration-size"],"定制 24.5")
        tap(button("item-composition")); tap(button("成双"))
        replace(app.textFields["spec-heelHeightCm"],"5.5")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertLessThanOrEqual(button("registration-save").frame.maxY,app.keyboards.firstMatch.frame.minY+1)
        shot("01-registration-specification-real-keyboard")
        tap(button("返回")); tap(button("保存草稿并退出"))
        XCTAssertTrue(app.navigationBars["服饰详情"].waitForExistence(timeout:8))
        returnToList(); edit(101)
        XCTAssertTrue(app.alerts["发现未完成的物品草稿"].waitForExistence(timeout:8)); tap(button("继续草稿"))
        XCTAssertEqual(app.textFields["registration-name"].value as? String,"回归·登记完成")
        tap(app.textFields["spec-heelHeightCm"])
        XCTAssertEqual(app.textFields["spec-heelHeightCm"].value as? String,"5.5")
        shot("02-registration-draft-restored-after-relaunch")
        tap(button("registration-save")); XCTAssertTrue(app.navigationBars["服饰详情"].waitForExistence(timeout:8))
        text("回归·登记完成"); shot("03-registration-saved")
    }
    func test02ActualPhotoPickerMultipleDetailsAndExplicitCover() {
        begin(); edit(101)
        choosePhotos("服饰照片")
        tap(button("set-cover-2"))
        shot("04-explicit-new-cover")
        choosePhotos("尺码／详情图")
        shot("05-multiple-detail-images")
        tap(button("registration-save")); XCTAssertTrue(app.navigationBars["服饰详情"].waitForExistence(timeout:8))
        shot("06-registration-with-photos-saved")
    }
    func test03DiscardPhotoAndTextChangesPreservesCommittedAndSharedImages() {
        begin(); edit(101)
        replace(app.textFields["registration-name"],"不应保存的名字")
        tap(button("photo-remove-服饰照片-1"))
        tap(button("photo-remove-尺码／详情图-0"))
        shot("07-remove-images-in-uncommitted-editor")
        tap(button("返回")); tap(button("放弃更改"))
        XCTAssertTrue(app.navigationBars["服饰详情"].waitForExistence(timeout:8)); text("回归·登记完成")
        returnToList(); edit(101)
        XCTAssertFalse(app.alerts["发现未完成的物品草稿"].exists)
        XCTAssertEqual(app.textFields["registration-name"].value as? String,"回归·登记完成")
        tap(button("photo-remove-服饰照片-2"))
        tap(button("返回")); tap(button("放弃更改"))
        shot("08-cancel-restored-original-registration")
    }
    func test04CreateCabinetShelfAndAssignOwnedItem() {
        begin(); room(101)
        tap(button("add-storage-node")); replace(app.textFields["storage-name"],"回归柜架")
        shot("09-create-cabinet-real-keyboard"); tap(button("storage-save"))
        XCTAssertTrue(app.navigationBars["分层收纳"].waitForExistence(timeout:8))
        tap(button("add-storage-node")); replace(app.textFields["storage-name"],"回归层格")
        tap(button("storage-parent")); tap(button("回归柜架")); tap(button("storage-save"))
        tap(button("assign-node-2")); tap(button("storage-item-103"))
        XCTAssertEqual(button("storage-item-103").value as? String,"已选择")
        XCTAssertFalse(button("storage-item-102").exists,"待尾款物品不能新增收纳")
        tap(button("storage-members-save")); shot("10-cabinet-shelf-owned-membership")
    }
    func test05MovingSubtreeMovesItemAndPersistedDraftToAnotherRoom() {
        begin(); edit(103); replace(app.textFields["registration-name"],"收纳中的未完成草稿")
        tap(button("返回")); tap(button("保存草稿并退出"))
        returnToList(); room(101); tap(button("move-node-1"))
        tap(button("storage-room")); tap(button("回归衣帽间"))
        shot("11-move-cabinet-and-subtree")
        tap(button("storage-move-save")); XCTAssertTrue(app.navigationBars["分层收纳"].waitForExistence(timeout:8))
        returnToList(); room(102); text("回归衣帽间 → 回归柜架 → 回归层格")
        shot("12-subtree-in-destination-room")
        returnToList(); edit(103); tap(button("继续草稿"))
        XCTAssertEqual(app.textFields["registration-name"].value as? String,"收纳中的未完成草稿")
        XCTAssertTrue(button("storage-room").label.contains("回归衣帽间"),app.debugDescription)
        XCTAssertTrue(button("storage-node").label.contains("回归衣帽间 → 回归柜架 → 回归层格"),app.debugDescription)
        shot("13-draft-placement-moved-with-subtree")
        tap(button("返回")); tap(button("放弃更改"))
    }
    func test06UnownedEditorAndStoragePickerCannotAddPlacement() {
        begin(); edit(102)
        text("仅已拥有物品可设置收纳位置")
        XCTAssertFalse(button("storage-room").exists)
        shot("14-unowned-storage-restricted-legacy-position-retained")
        tap(button("返回"))
        returnToList(); room(102); tap(button("assign-node-2"))
        XCTAssertFalse(button("storage-item-102").exists)
        XCTAssertTrue(button("storage-item-103").exists)
        XCTAssertEqual(button("storage-item-103").value as? String,"已选择")
        shot("15-owned-only-storage-picker")
        tap(button("取消"))
    }
    func test07RenamingCategoryRetainsStableTypeAndSpecifications() {
        begin(); tap(app.tabBars.buttons["个人"]); tap(button("attribute-settings")); tap(button("category-management")); tap(button("鞋子"))
        replace(app.textFields["名称"],"回归鞋履")
        shot("16-category-rename-stable-type")
        tap(button("保存"))
        returnToList(); edit(101)
        text("回归鞋履"); tap(app.textFields["spec-heelHeightCm"])
        XCTAssertEqual(app.textFields["spec-heelHeightCm"].value as? String,"5.5")
        shot("17-renamed-category-keeps-footwear-specifications")
        tap(button("返回"))
    }
    func test08DeleteStorageExplicitlyKeepsItemLedgerAndPhotos() {
        begin(); room(102)
        tap(button("add-storage-node")); replace(app.textFields["storage-name"],"回归待删位置"); tap(button("storage-save"))
        let row=app.cells.containing(.staticText,identifier:"回归衣帽间 → 回归待删位置").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout:8),app.debugDescription)
        let editNodeButton = row.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'edit-node-'")).firstMatch
        let id = Int(editNodeButton.identifier.replacingOccurrences(of:"edit-node-",with:""))!
        tap(button("assign-node-\(id)")); XCTAssertTrue(button("storage-item-103").waitForExistence(timeout:8))
        XCTAssertEqual(button("storage-item-103").value as? String,"未选择","新增位置不能继承其他位置的勾选")
        tap(button("storage-item-101")); tap(button("storage-members-save"))
        row.swipeLeft(); tap(button("删除")); shot("18-explicit-delete-contents-warning")
        tap(button("删除位置，物品移至未设置"))
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == false"),object:button("edit-node-\(id)"))],timeout:8),.completed)
        returnToList(); edit(101)
        XCTAssertEqual(app.textFields["registration-name"].value as? String,"回归·登记完成")
        text("未设置"); tap(button("photo-remove-服饰照片-2"))
        tap(button("返回")); tap(button("放弃更改"))
        shot("19-item-and-photos-survive-storage-deletion")
    }
    func test09DarkLargeTextNewRegistrationWithActualKeyboard() {
        begin(); tap(button("新增服饰"))
        replace(app.textFields["registration-name"],"回归·大字登记")
        let keyboard=app.keyboards.firstMatch, field=app.textFields["registration-name"], save=button("registration-save")
        XCTAssertTrue(keyboard.exists); XCTAssertTrue(save.isHittable)
        XCTAssertLessThanOrEqual(field.frame.maxY,keyboard.frame.minY+1)
        XCTAssertLessThanOrEqual(save.frame.maxY,keyboard.frame.minY+1)
        shot("20-dark-accessibility-registration-real-keyboard")
        tap(save); XCTAssertTrue(button("新增服饰").waitForExistence(timeout:8)); text("回归·大字登记")
        shot("21-dark-accessibility-registration-saved")
    }
    func test10CustomSizeReplacementAndDetailImagePaging() {
        begin(); edit(101)
        replace(app.textFields["registration-size"],"定制 24.5")
        shot("22-custom-size-exact-replacement")
        tap(button("registration-save")); XCTAssertTrue(app.navigationBars["服饰详情"].waitForExistence(timeout:8))
        tap(app.staticTexts["1 / 2"].firstMatch)
        for _ in 0..<8 {
            let pages = app.images.matching(NSPredicate(format:"label == %@","第1张照片")).allElementsBoundByIndex.filter { $0.frame.width > 200 && $0.frame.midX > 0 && $0.frame.midX < app.frame.width }
            guard let last = pages.max(by: { $0.frame.midY < $1.frame.midY }) else { break }
            let y = last.frame.midY
            if y > 180 && y < 680 { break }
            let distance = min(180,abs(350-y)) / app.frame.height
            let startY: CGFloat = y < 180 ? 0.25 : 0.72
            let endY = y < 180 ? startY + distance : startY - distance
            app.coordinate(withNormalizedOffset:CGVector(dx:0.95,dy:startY)).press(forDuration:0.05,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.95,dy:endY)),withVelocity:.slow,thenHoldForDuration:0.2)
        }
        let pages = app.images.matching(NSPredicate(format:"label == %@","第1张照片")).allElementsBoundByIndex
        let visible = pages.first { $0.frame.height > 0 && $0.frame.midY > 130 && $0.frame.midY < 740 && $0.frame.midX > 0 && $0.frame.midX < app.frame.width }
        XCTAssertNotNil(visible,app.debugDescription)
        guard let visible else { return }
        visible.coordinate(withNormalizedOffset:CGVector(dx:0.8,dy:0.5)).press(forDuration:0.05,thenDragTo:visible.coordinate(withNormalizedOffset:CGVector(dx:0.2,dy:0.5)))
        XCTAssertTrue(app.staticTexts["2 / 2"].firstMatch.waitForExistence(timeout:8),app.debugDescription)
        shot("23-detail-image-second-page")
        let second = app.images.matching(NSPredicate(format:"label == %@","第2张照片")).allElementsBoundByIndex.first { $0.frame.height > 0 && $0.frame.midY > 130 && $0.frame.midY < 740 && $0.frame.midX > 0 && $0.frame.midX < app.frame.width }
        XCTAssertNotNil(second,app.debugDescription)
        second?.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap()
        XCTAssertTrue(button("关闭照片").waitForExistence(timeout:8)); shot("24-detail-image-original-fullscreen")
        tap(button("关闭照片"))
    }

}
#endif
