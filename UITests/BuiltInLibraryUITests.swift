#if os(iOS)
import XCTest

@MainActor
final class BuiltInLibraryUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.lolita.ios")
    private func button(_ id: String) -> XCUIElement { app.buttons[id].firstMatch }
    private func begin() {
        continueAfterFailure = false
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch(); XCTAssertTrue(button("新增服饰").waitForExistence(timeout: 25), app.debugDescription)
    }
    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        _ = element.waitForExistence(timeout: 4)
        for attempt in 0..<18 {
            if element.exists && element.isHittable && element.frame.height > 0 {
                let f = element.frame
                let topControl = f.height <= 110 && f.minY >= 40 && f.minY < 170
                let saveControl = ["builtin-adopt-storage", "storage-save"].contains(element.identifier)
                if saveControl || topControl || f.height < 70 || (f.midY > 130 && f.midY < app.frame.height - 110) { element.tap(); return }
            }
            let down = element.exists && element.frame.height > 0 ? element.frame.minY < 120 : (attempt / 5) % 2 == 1
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: down ? 0.25 : 0.72)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: down ? 0.72 : 0.25)))
        }
        XCTFail(app.debugDescription, file: file, line: line)
    }
    private func shot(_ title: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = title; image.lifetime = .keepAlways; add(image)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = title + "-hierarchy"; tree.lifetime = .keepAlways; add(tree)
    }
    private func back() { tap(app.navigationBars.buttons.element(boundBy: 0)) }
    private func openRoom(_ name: String) {
        tap(app.tabBars.buttons["首页"]); tap(button("位置"))
        let room = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "location-", name)).firstMatch
        tap(room); XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 10), app.debugDescription)
    }
    func test01RoomArtworkCancelSaveAndColdRestart() {
        begin(); tap(button("位置")); shot("01-six-default-room-cards")
        openRoom("卧室"); shot("02-bedroom-original-artwork")
        tap(button("编辑位置")); tap(button("choose-builtin-room")); shot("03-six-room-artwork-choices")
        tap(button("builtin-room-书房")); back(); tap(button("放弃"))
        XCTAssertTrue(app.navigationBars["卧室"].waitForExistence(timeout: 8)); shot("04-room-edit-cancel-keeps-original")
        tap(button("编辑位置")); tap(button("choose-builtin-room")); tap(button("builtin-room-书房")); tap(button("保存"))
        XCTAssertTrue(app.navigationBars["卧室"].waitForExistence(timeout: 8)); shot("05-room-artwork-saved")
        app.terminate(); app.launch(); XCTAssertTrue(button("新增服饰").waitForExistence(timeout: 20)); openRoom("卧室"); shot("06-room-artwork-after-restart")
    }
    func test02AdoptFourStorageTemplatesAndEditOne() {
        begin(); openRoom("卧室"); tap(button("manage-storage")); tap(button("choose-builtin-storage")); shot("07-storage-artwork-choices")
        for id in ["wig_stand", "shoe_cabinet", "sock_drawer", "accessory_box"] { tap(button("builtin-storage-" + id)) }
        tap(button("builtin-adopt-storage")); XCTAssertTrue(app.navigationBars["分层收纳"].waitForExistence(timeout: 12)); shot("08-adopted-storage-with-photos")
        let edit = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "edit-node-")).firstMatch
        tap(edit); XCTAssertTrue(app.navigationBars["编辑收纳位置"].waitForExistence(timeout: 8), app.debugDescription)
        let name = app.textFields["storage-name"].firstMatch; XCTAssertEqual(name.value as? String, "假发架"); tap(name)
        name.press(forDuration: 1.1)
        if button("全选").waitForExistence(timeout: 2) { tap(button("全选")); name.typeText("回归·已编辑的假发架") }
        else { name.tap(withNumberOfTaps: 3, numberOfTouches: 1); name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (name.value as? String ?? "").count) + "回归·已编辑的假发架") }
        tap(button("storage-save")); XCTAssertTrue(app.navigationBars["分层收纳"].waitForExistence(timeout: 8)); shot("09-template-can-be-edited")
        app.terminate(); app.launch(); XCTAssertTrue(button("新增服饰").waitForExistence(timeout: 20)); openRoom("卧室"); tap(button("manage-storage"))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "回归·已编辑的假发架")).firstMatch.waitForExistence(timeout: 8)); shot("10-storage-after-restart")
    }
    func test03BrandLogoRemovalAndRoomDeletionAreNotReapplied() {
        begin(); tap(app.tabBars.buttons["个人"]); tap(button("attribute-settings")); tap(button("brand-management"))
        let search = app.searchFields.firstMatch; tap(search); search.typeText("花与珍珠匣")
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "花与珍珠匣")).firstMatch
        tap(row); XCTAssertTrue(button("移除品牌图片").waitForExistence(timeout: 8), app.debugDescription); shot("11-default-brand-logo")
        tap(button("移除品牌图片")); tap(button("保存"))
        XCTAssertTrue(app.navigationBars["编辑品牌"].waitForNonExistence(timeout: 12), app.debugDescription)
        app.terminate(); app.launch(); XCTAssertTrue(button("新增服饰").waitForExistence(timeout: 20))
        tap(app.tabBars.buttons["个人"]); tap(button("attribute-settings")); tap(button("brand-management")); tap(app.searchFields.firstMatch); app.searchFields.firstMatch.typeText("花与珍珠匣"); tap(row)
        XCTAssertFalse(button("移除品牌图片").exists, app.debugDescription); shot("12-removed-logo-stays-removed"); tap(button("取消")); back(); back()
        tap(app.tabBars.buttons["首页"]); tap(button("位置")); openRoom("储物间")
        tap(button("location-more-actions")); tap(button("删除位置")); tap(app.alerts.buttons["删除"])
        XCTAssertTrue(app.navigationBars["储物间"].waitForNonExistence(timeout: 15), app.debugDescription)
        app.terminate(); app.launch(); XCTAssertTrue(button("新增服饰").waitForExistence(timeout: 20)); tap(button("位置"))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "location-", "储物间")).firstMatch.exists); shot("13-deleted-default-room-stays-deleted")
    }
}
#endif
