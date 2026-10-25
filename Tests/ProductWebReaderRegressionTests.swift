#if os(macOS) && canImport(WebKit)
import XCTest
import WebKit
@testable import lolita

@MainActor
private final class FixtureNavigation: NSObject, WKNavigationDelegate {
    var finished: (() -> Void)?
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finished?() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finished?() }
}
final class ProductWebReaderRegressionTests: XCTestCase {
    @MainActor func testProductionReaderRunsInWebKitAndReadsOnlyVisibleProductDOM() async throws {
        let configuration = WKWebViewConfiguration(); configuration.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame:CGRect(x:0,y:0,width:400,height:800),configuration:configuration)
        let delegate = FixtureNavigation(), loaded = XCTestExpectation(description:"离线商品 DOM 已加载")
        delegate.finished = { loaded.fulfill() }; web.navigationDelegate = delegate
        web.loadHTMLString(#"""
            <html><head><meta property="og:image" content="https://img.alicdn.com/public.jpg"></head><body>
            <h1>离线商品标题</h1><div class="priceText--test">100-200 起</div>
            <button aria-label="已选中 蓝色 M">蓝色 M</button><button style="display:none" aria-label="已选中 错误规格">隐藏</button>
            <div class="attributes-list">面料：棉</div><div class="detail-desc"><p>完整的纯文字详情</p></div>
            <input type="password" value="should-never-be-extracted"><script>window.privateAccount='should-never-be-extracted'</script>
            </body></html>
            """#,baseURL:URL(string:"https://item.taobao.com/item.htm?id=123"))
        let status = await XCTWaiter.fulfillment(of:[loaded],timeout:15)
        XCTAssertEqual(status,.completed)
        let raw: String = try await withCheckedThrowingContinuation { continuation in
            web.evaluateJavaScript(ProductSource.script) { value,error in
                if let error { continuation.resume(throwing:error) }
                else if let raw = value as? String { continuation.resume(returning:raw) }
                else { continuation.resume(throwing:ValidationError.invalid("未返回网页资料")) }
            }
        }
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(raw.utf8)) as? [String:Any])
        XCTAssertEqual(root["name"] as? String,"离线商品标题"); XCTAssertEqual(root["sku"] as? String,"已选中 蓝色 M")
        XCTAssertEqual(root["properties"] as? String,"面料：棉"); XCTAssertEqual(root["detailStatus"] as? String,"complete")
        XCTAssertEqual(root["photos"] as? [String],["https://img.alicdn.com/public.jpg"])
        XCTAssertFalse(raw.contains("should-never-be-extracted")); XCTAssertFalse(raw.contains("错误规格"))
        web.stopLoading()
    }
}
#endif
