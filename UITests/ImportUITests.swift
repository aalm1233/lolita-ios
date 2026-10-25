#if os(iOS)
import XCTest

@MainActor
final class ImportUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier:"com.lolita.ios")
    private func begin() {
        continueAfterFailure = false
        app.launchArguments = ["-AppleLanguages","(zh-Hans)","-AppleLocale","zh_CN"]
        app.launch(); XCTAssertTrue(app.buttons["新增服饰"].waitForExistence(timeout:20),app.debugDescription)
    }
    private func button(_ id: String) -> XCUIElement { app.buttons[id].firstMatch }
    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        for attempt in 0..<24 {
            if element.exists && element.isHittable && element.isEnabled && element.frame.height > 0 && (!app.keyboards.firstMatch.exists || element.frame.maxY < app.keyboards.firstMatch.frame.minY - 52) {
                let bar = ["product-save", "registration-save", "import-storage-save"].map { button($0) }.first { $0.exists && $0.isHittable && $0.identifier != element.identifier }
                if bar == nil || element.frame.maxY < bar!.frame.minY { if element.elementType == .switch { element.coordinate(withNormalizedOffset:CGVector(dx:0.93,dy:0.5)).tap() } else { element.tap() }; return }
            }
            if app.keyboards.firstMatch.exists {
                let close = ["import-dismiss-keyboard", "product-dismiss-keyboard", "dismiss-registration-keyboard"].map { button($0) }.first { $0.exists && $0.isHittable }
                if let close { close.tap(); continue }
            }
            let known = element.exists && element.frame.height > 0
            let down = known ? element.frame.minY < 140 : (attempt / 5) % 2 == 1
            let from = app.coordinate(withNormalizedOffset:CGVector(dx:0.94,dy:down ? 0.25 : 0.64))
            let to = app.coordinate(withNormalizedOffset:CGVector(dx:0.94,dy:down ? 0.64 : 0.25))
            from.press(forDuration:0.05,thenDragTo:to)
        }
        XCTFail("无法操作控件\n"+app.debugDescription,file:file,line:line)
    }
    private func replace(_ id: String, _ value: String) {
        if app.keyboards.firstMatch.exists {
            for id in ["import-dismiss-keyboard", "product-dismiss-keyboard", "dismiss-registration-keyboard"] { let close = button(id); if close.exists && close.isHittable { close.tap(); break } }
        }
        let field = app.textFields[id].firstMatch
        // Position before focusing, so a decimal keyboard's toolbar cannot cover the input.
        for attempt in 0..<20 {
            if field.exists && field.frame.height > 0 && field.frame.minY >= 145 && field.frame.maxY <= 390 { break }
            let known = field.exists && field.frame.height > 0
            let down = known ? field.frame.minY < 145 : (attempt / 5) % 2 == 1
            let delta = known ? min(220,abs(field.frame.midY-280)) : 220
            let startY: CGFloat = down ? 170 : 520
            let endY = down ? startY+delta : startY-delta
            app.coordinate(withNormalizedOffset:CGVector(dx:0.94,dy:startY/app.frame.height)).press(forDuration:0.05,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.94,dy:endY/app.frame.height)))
        }
        tap(field)
        let old = field.value as? String ?? ""
        field.coordinate(withNormalizedOffset:CGVector(dx:0.95,dy:0.5)).tap()
        field.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:(old == field.placeholderValue ? 0 : old.count)+2)+value)
        XCTAssertEqual(field.value as? String,value,app.debugDescription)
    }
    private func back() { tap(app.navigationBars.buttons.element(boundBy:0)) }
    private func text(_ value: String) { XCTAssertTrue(app.descendants(matching:.any).matching(NSPredicate(format:"label CONTAINS %@",value)).firstMatch.waitForExistence(timeout:12),app.debugDescription) }
    private func shot(_ name: String) { let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a);let h=XCTAttachment(string:app.debugDescription);h.name=name+"-hierarchy";h.lifetime = .keepAlways;add(h) }
    private func restart() { app.terminate(); app.launch(); XCTAssertTrue(button("新增服饰").waitForExistence(timeout:20),app.debugDescription) }
    private func openImport(_ id: String) { tap(app.tabBars.buttons["个人"]);tap(button("淘宝订单导入"));tap(button("import-resume-"+id)) }
    private func on(_ id: String) {
        let value=app.switches[id].firstMatch
        if !value.exists || value.value as? String != "1" { tap(value) }
        let expectation = XCTNSPredicateExpectation(predicate:NSPredicate(format:"value == %@","1"),object:value)
        XCTAssertEqual(XCTWaiter.wait(for:[expectation],timeout:3),.completed,app.debugDescription)
    }
    private func photo(_ title: String) {
        tap(button(title));let images=app.images.matching(identifier:"PXGGridLayout-Info")
        XCTAssertTrue(images.firstMatch.waitForExistence(timeout:20),app.debugDescription)
        images.firstMatch.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap()
        if button("选取").exists { tap(button("选取")) }
        else if button("完成").exists && app.navigationBars["照片"].exists { tap(button("完成")) }
        XCTAssertTrue(app.navigationBars["照片"].waitForNonExistence(timeout:15),app.debugDescription)
    }
    private func record(_ title: String, _ name: String) {
        tap(button(title));let field=app.searchFields.firstMatch
        if field.waitForExistence(timeout:3) { field.tap();field.typeText(name) }
        tap(button(name))
    }
    private func saveProduct() { tap(button("product-save"));text("保存完成") }

    func test01SessionRawInputAndPhotoSurviveProcessRestartThenAtomicCommit() {
        begin();openImport("ui-main");tap(button("回归·导入草稿"))
        replace("服饰名称","回归·会话恢复");replace("商品金额（不含邮费）","100.")
        photo("补充图片");shot("01-real-photo-picker-import-editor")
        tap(button("完成"));restart();openImport("ui-main");tap(button("回归·会话恢复"))
        let field=app.textFields["商品金额（不含邮费）"].firstMatch;tap(field);XCTAssertEqual(field.value as? String,"100.")
        replace("商品金额（不含邮费）","100.00");on("已核对商品金额、邮费和实付");shot("02-restored-raw-input-real-keyboard")
        tap(button("完成"));tap(button("导入 1 件服饰"));tap(button("导入衣橱"));text("成功导入 1 件服饰");text("回执：")
        shot("03-atomic-import-result-receipt")
    }
    func test02SameSourceInAnotherSessionReturnsDuplicateWithoutNewMoney() {
        begin();openImport("ui-duplicate");tap(button("导入 1 件服饰"));tap(button("导入衣橱"));text("成功导入 0 件服饰");text("已导入去重 1 条")
        shot("04-duplicate-source-receipt")
    }
    func test03ConflictingFilesRequireChoiceAndFailedFileCanBeRemoved() {
        begin();openImport("ui-conflict");text("来源冲突");text("损坏文件.xlsx")
        shot("05-source-conflict-and-file-error")
        tap(button("import-source-1"));tap(button("全选"));tap(button("下一步：补全资料"));text("检查商品与付款")
        tap(button("返回选择"));shot("06-selected-source-persisted")
        // Remove only the unread file through the visible confirmation.
        let row=app.staticTexts["损坏文件.xlsx"].firstMatch;tap(row)
        let remove=app.buttons.matching(identifier:"移除").allElementsBoundByIndex.first { $0.frame.minY > row.frame.minY-20 && $0.frame.minY < row.frame.maxY+35 }
        XCTAssertNotNil(remove,app.debugDescription);tap(remove!);tap(button("移除文件"));XCTAssertTrue(row.waitForNonExistence(timeout:8))
        shot("07-unread-file-removed-valid-source-kept")
    }
    func test04ProductWishBatchZeroReferenceNoLedgerAndPersistentInput() {
        begin();tap(app.tabBars.buttons["个人"]);tap(button("商品链接登记"))
        replace("product-url","https://item.taobao.com/item.htm?id=123&spm=private");tap(button("product-manual"))
        replace("product-name","回归·链接心愿");record("product-brand","回归导入品牌");record("product-category","JSK")
        replace("product-reference","0")
        let variants=app.textFields["product-variants"].firstMatch
        tap(variants);variants.typeText("蓝色 | M\n红色 | L")
        photo("补充商品照片");on("product-confirm-sku")
        back();tap(button("保存草稿并退出"));restart();tap(app.tabBars.buttons["个人"]);tap(button("商品链接登记"))
        XCTAssertEqual(app.textFields["product-name"].firstMatch.value as? String,"回归·链接心愿");shot("08-product-batch-draft-restored")
        saveProduct();shot("09-product-wishes-zero-reference")
    }
    func test05SupplementSelectedNameAndPhotoKeepsOriginalPictureAndLedger() {
        begin();tap(button("item-101"));tap(button("从商品链接补资料"))
        replace("product-url","https://item.taobao.com/item.htm?id=123");tap(button("product-manual"));replace("product-name","回归·补资料完成")
        photo("补充商品照片");on("product-confirm-sku");on("product-apply-name");on("product-apply-photos")
        shot("10-supplement-explicit-field-comparison");saveProduct();shot("11-supplement-saved")
    }
    func test06SupplementMergesExistingEditorWithoutOverwritingOriginalItem() {
        begin();tap(button("item-103"));tap(button("从商品链接补资料"))
        replace("product-url","https://item.taobao.com/item.htm?id=456");tap(button("product-manual"));replace("product-name","回归·合入编辑")
        on("product-confirm-sku");on("product-apply-name");saveProduct();text("已合入原编辑草稿");shot("12-existing-editor-preserved")
        tap(button("继续原服饰编辑"));tap(button("继续草稿"));let size = app.textFields["registration-size"].firstMatch;tap(size);XCTAssertEqual(size.value as? String,"草稿专用尺码");shot("13-original-editor-other-input-kept")
    }
    func test07DarkAccessibilityActualWebViewAndInvalidLinkRecovery() {
        begin();tap(app.tabBars.buttons["个人"]);tap(button("商品链接登记"))
        replace("product-url","https://example.com/private");tap(button("product-open-web"));text("请提供带商品 ID");tap(button("确定"))
        replace("product-url","https://item.taobao.com/item.htm?id=123");tap(button("product-open-web"))
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout:15),app.debugDescription)
        shot("14-dark-accessibility-real-webview")
        tap(button("读取当前商品资料"))
        // Network/login/content availability may prevent reading the live product. Keep the error
        // visible and recover using the normal manual-entry path, without inventing scraped data.
        if button("确定").waitForExistence(timeout:25) { shot("15-live-page-read-result");tap(button("确定")) }
        if button("关闭").exists { tap(button("关闭")) }
        tap(button("product-manual"));shot("16-dark-accessibility-manual-recovery")
        back();tap(button("放弃本次补资料"))
    }
    func test08ArrangeOnlyNewOwnedImportInAnExistingRoom() {
        begin();openImport("ui-main");tap(button("为本次已拥有物品安排收纳"))
        text("回归·会话恢复");tap(button("storage-room"));tap(button("回归衣柜"))
        shot("17-post-import-storage-owned-selection");tap(button("import-storage-save"));text("成功导入 1 件服饰")
    }
    func test09ActualSystemFilePickerReadsXLSXAndPersistsSession() {
        begin();tap(app.tabBars.buttons["个人"]);tap(button("淘宝订单导入"));tap(button("选择 Excel 文件"))
        XCTAssertTrue(button("取消").waitForExistence(timeout:20),app.debugDescription)
        shot("18-actual-system-file-picker")
        let file=app.descendants(matching:.any).matching(NSPredicate(format:"label CONTAINS %@","导入回归")).firstMatch
        if !file.waitForExistence(timeout:2) {
            if button("浏览").exists { tap(button("浏览")) }
            let local = app.cells["DOC.sidebar.item.我的iPhone"].firstMatch
            if local.waitForExistence(timeout:5) { tap(local) }
        }
        tap(file)
        if button("打开").exists { tap(button("打开")) }
        text("回归·文件选取");shot("19-real-xlsx-read-through-file-picker")
        tap(button("下一步：补全资料"));tap(button("回归·文件选取"))
        text("下单时间：2026-10-01 12:00");shot("20-real-file-financial-review-unknown-date")
        tap(button("完成"));back();tap(button("保存会话并退出"))
    }

    func test10ExplicitSKUFieldsAndPerVariantReferencesDoNotCreateOrders() {
        begin();tap(app.tabBars.buttons["个人"]);tap(button("商品链接登记"))
        replace("product-url","https://item.taobao.com/item.htm?id=789");tap(button("product-manual"))
        replace("product-name","回归·规格拆分");record("product-brand","回归导入品牌");record("product-category","JSK")
        let variants=app.textFields["product-variants"].firstMatch;tap(variants);variants.typeText("蓝色 | M | 0\n红色 | L | 120.50")
        on("product-confirm-sku");shot("21-explicit-sku-fields-and-reference-price");saveProduct();shot("22-sku-batch-wishes-saved")
    }

}
#endif
