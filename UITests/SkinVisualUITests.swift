#if os(iOS)
import XCTest

/// Shipping controls only. No launch-time theme or database bypasses.
@MainActor
final class SkinVisualUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.lolita.ios")
    private let themes = ["甜美粉", "哥特暗黑", "中华风韵", "经典优雅", "清风水手", "田园牧歌", "维多利亚"]
    private func button(_ id: String) -> XCUIElement { app.buttons[id].firstMatch }
    private func begin() {
        continueAfterFailure = false
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(button("新增服饰").waitForExistence(timeout: 25), app.debugDescription)
    }
    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        if !element.exists { _ = element.waitForExistence(timeout: 3) }
        for attempt in 0..<20 {
            if element.exists && element.isHittable && element.frame.height > 0 {
                let frame = element.frame
                let tab = ["首页", "穿搭", "统计", "个人"].contains(element.label)
                let topControl = frame.height < 70 && frame.minY >= 50 && frame.minY < 170
                if tab || topControl || (frame.midY > 120 && frame.midY < app.frame.height - 100) { element.tap(); return }
            }
            let down = element.exists && element.frame.height > 0 ? element.frame.minY < 115 : (attempt / 5) % 2 == 1
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: down ? 0.25 : 0.7)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: down ? 0.7 : 0.25)))
        }
        XCTFail("无法操作控件\n" + app.debugDescription, file: file, line: line)
    }
    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-hierarchy"; tree.lifetime = .keepAlways; add(tree)
    }
    private func back() { tap(app.navigationBars.buttons.element(boundBy: 0)) }
    private func selectTheme(_ name: String) {
        tap(app.tabBars.buttons["个人"])
        tap(button("theme-settings"))
        tap(button(name))
        XCTAssertEqual(button(name).value as? String, "当前主题", app.debugDescription)
    }

    func test01EverySkinPersistsAndUpdatesAllFourTabs() {
        begin()
        for (index, name) in themes.enumerated() {
            selectTheme(name)
            shot("\(index)-theme")
            back()
            app.terminate(); app.launch()
            XCTAssertTrue(button("新增服饰").waitForExistence(timeout: 25))
            tap(button("服饰")); shot("\(index)-home")
            tap(button("搜索"))
            let search = app.textFields["搜索服饰"].firstMatch
            tap(search); search.typeText("视觉检查无匹配")
            XCTAssertTrue(app.staticTexts["没有找到匹配结果"].waitForExistence(timeout: 8), app.debugDescription)
            tap(button("清除搜索")); XCTAssertTrue(["", "搜索服饰"].contains(search.value as? String ?? ""))
            tap(button("取消搜索")); XCTAssertTrue(button("新增服饰").exists)
            tap(app.tabBars.buttons["穿搭"]); shot("\(index)-outfits")
            tap(app.tabBars.buttons["统计"]); shot("\(index)-stats")
            tap(app.tabBars.buttons["个人"]); shot("\(index)-profile")
        }
    }

    func test02StyledActionsKeepPhotoEditorAndMenusUsable() {
        begin(); selectTheme("甜美粉"); back(); tap(app.tabBars.buttons["首页"]); tap(button("服饰"))
        tap(button("排序：更新时间：新到旧")); shot("actions-sort-menu"); tap(button("更新时间：新到旧"))
        for title in ["三列网格", "画廊", "列表", "两列网格"] {
            let toggle = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "展示方式：")).firstMatch
            tap(toggle); XCTAssertTrue(toggle.label.contains(title), app.debugDescription)
        }
        tap(button("筛选，已选 0 项")); XCTAssertTrue(app.navigationBars["筛选服饰"].waitForExistence(timeout: 8), app.debugDescription)
        shot("actions-filter"); tap(button("完成"))
        tap(button("搜索")); let search = app.textFields["搜索服饰"].firstMatch; tap(search); search.typeText("回归·补资料完成"); tap(button("取消搜索"))
        tap(button("item-101")); XCTAssertTrue(app.navigationBars["服饰详情"].waitForExistence(timeout: 10), app.debugDescription)
        shot("actions-old-photos-detail")
        tap(button("更多服饰操作")); shot("actions-styled-menu"); XCTAssertTrue(button("删除服饰").waitForExistence(timeout: 8), app.debugDescription)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.4)).tap()
        XCTAssertFalse(app.alerts.firstMatch.exists, app.debugDescription)
        tap(button("编辑服饰")); XCTAssertTrue(app.navigationBars["编辑服饰"].waitForExistence(timeout: 10), app.debugDescription)
        shot("actions-editor-cancel")
        tap(button("add-photos-服饰照片")); XCTAssertTrue(app.navigationBars["照片"].waitForExistence(timeout: 15), app.debugDescription)
        shot("actions-system-photo-picker"); tap(button("取消"))
        back(); XCTAssertTrue(app.navigationBars["服饰详情"].waitForExistence(timeout: 10))
        back(); selectTheme("甜美粉"); back()
    }

    func test05FinalSkinScreenshots() {
        begin()
        for (index, name) in themes.enumerated() {
            selectTheme(name); shot("\(index)-theme"); back()
            tap(app.tabBars.buttons["首页"]); tap(button("服饰")); shot("\(index)-home")
            tap(app.tabBars.buttons["穿搭"]); shot("\(index)-outfits")
            tap(app.tabBars.buttons["统计"]); shot("\(index)-stats")
            tap(app.tabBars.buttons["个人"]); shot("\(index)-profile")
        }
    }

    func test04LauncherIconOpensThePreservedWardrobe() {
        begin(); XCUIDevice.shared.press(.home); XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        var visibleIcon: XCUIElement?
        for _ in 0..<3 {
            visibleIcon = springboard.icons.matching(identifier: "Lolita").allElementsBoundByIndex.first { $0.isHittable && $0.frame.width > 0 }
            if visibleIcon != nil { break }
            springboard.swipeLeft()
        }
        guard let icon = visibleIcon else { XCTFail(springboard.debugDescription); return }
        let attachment = XCTAttachment(screenshot: springboard.screenshot()); attachment.name = "launcher-installed"; attachment.lifetime = .keepAlways; add(attachment)
        icon.tap(); XCTAssertTrue(button("新增服饰").waitForExistence(timeout: 15)); shot("launcher-wardrobe-opened")
    }

    func test03SystemAccessibilityTextWithDarkArtwork() {
        begin(); selectTheme("哥特暗黑"); shot("accessibility-theme-grid"); back()
        tap(app.tabBars.buttons["首页"])
        let tabs = app.scrollViews["compact-page-tabs"].firstMatch
        tabs.swipeLeft(); tap(button("心愿")); XCTAssertTrue(button("新增心愿").exists)
        tabs.swipeRight(); tap(button("服饰")); shot("accessibility-home")
        let total = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "合计 ")).firstMatch
        XCTAssertTrue(total.exists); XCTAssertLessThan(total.frame.height, 80)

        tap(app.tabBars.buttons["穿搭"]); shot("accessibility-outfits")
        tap(app.tabBars.buttons["统计"]); shot("accessibility-stats")
        tap(app.tabBars.buttons["个人"]); shot("accessibility-profile")
        selectTheme("甜美粉"); back()
    }
}
#endif
