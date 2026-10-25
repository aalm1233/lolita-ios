import Foundation

struct ProductCandidate: Codable, Sendable, Equatable {
    var publicURL: String
    var name = ""
    var properties = ""
    var selectedSKU = ""
    var priceText = ""
    var photoURLs: [String] = []
    var detailURLs: [String] = []
    var warnings: [String] = []
}
struct ProductImportSnapshot: Codable, Sendable, Equatable {
    var targetItemId: Int64? = nil
    var baselineUpdatedAt: Int64? = nil
    var baselineDraftHash: String? = nil
    var input = ""
    var candidate: ProductCandidate? = nil
    var name = ""
    var properties = ""
    var size = ""
    var color = ""
    var variants = ""
    var brandId: Int64 = 0
    var categoryId: Int64 = 0
    var referenceText = ""
    var selectedFields: Set<String> = []
    var confirmedSKU = false
    var savedItemIds: [Int64] = []
    var returnedDraftId: String? = nil
    var operationId = UUID().uuidString
}

struct ProductVariant: Sendable, Equatable {
    var color: String
    var size: String
    var referenceCents: Int64?
    var title: String { [color, size].filter { !$0.isEmpty }.joined(separator: " ") }
}

enum ProductSource {
    static func variants(_ text: String, commonReference: String) throws -> [ProductVariant] {
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard lines.count <= 30 else { throw ValidationError.invalid("单批最多 30 件，请分批登记") }
        let fallback = commonReference.isEmpty ? nil : try OrderImportSource.money(commonReference)
        var keys = Set<String>()
        return try lines.map { line in
            let parts = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard (2...3).contains(parts.count), (!parts[0].isEmpty || !parts[1].isEmpty), parts[0].count <= 100, parts[1].count <= 100,
                  keys.insert(parts[0] + "|" + parts[1]).inserted else { throw ValidationError.invalid("每行请填写“颜色 | 尺码 | 参考价”，参考价可省，同一规格不能重复") }
            return ProductVariant(color: parts[0], size: parts[1], referenceCents: parts.count == 3 && !parts[2].isEmpty ? try OrderImportSource.money(parts[2]) : fallback)
        }
    }
    static func draftFingerprint(_ draft: ItemDraft) -> String { OrderImportSource.hash([draft.id, draft.dataJson, String(draft.baselineUpdatedAt ?? -1), String(draft.updatedAt), String(draft.imagePaths.values.count), String(draft.detailImagePaths.values.count)].joined(separator: "|")) }
    static func shortURL(_ raw: String) -> String? {
        guard let c = URLComponents(string: raw), c.scheme == "https", c.host?.lowercased() == "e.tb.cn", c.user == nil, c.password == nil, c.port == nil || c.port == 443, !c.path.isEmpty else { return nil }
        return c.url?.absoluteString
    }
    static func shareURL(_ text: String) -> String? {
        if let url = OrderImportSource.publicURL(text) ?? shortURL(text) { return url }
        let regex = try? NSRegularExpression(pattern: "https?://[^\\s<>\\\"，。]+")
        for match in regex?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? [] {
            if let range = Range(match.range, in: text), let url = OrderImportSource.publicURL(String(text[range])) ?? shortURL(String(text[range])) { return url }
        }
        return nil
    }
    static func imageURL(_ text: String) -> URL? {
        let raw = text.hasPrefix("//") ? "https:" + text : text
        guard var c = URLComponents(string: raw), ["http", "https"].contains(c.scheme ?? ""), c.user == nil, c.password == nil, c.port == nil,
              let host = c.host?.lowercased(), host == "alicdn.com" || host.hasSuffix(".alicdn.com") else { return nil }
        c.scheme = "https"; return c.url
    }
    static func parse(_ raw: String, expectedURL: String) throws -> ProductCandidate {
        guard raw.utf8.count <= 2_000_000, let data = raw.data(using: .utf8), let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let url = object["url"] as? String, let canonical = OrderImportSource.publicURL(url), canonical == expectedURL || shortURL(expectedURL) != nil else { throw ValidationError.invalid("网页商品已变化或不是受支持的淘宝／天猫商品，请重新打开后读取") }
        guard object["detailStatus"] as? String != "pending" else { throw ValidationError.invalid("商品详情尚未加载完整，请在网页展开详情并滚动加载后再读取") }
        let name = (object["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 500 else { throw ValidationError.invalid("未读取到商品名称，请在网页完成加载或登录后重试，也可手动填写") }
        func images(_ key: String) -> [String] { var seen = Set<String>(); return (object[key] as? [String] ?? []).compactMap { imageURL($0)?.absoluteString }.filter { seen.insert($0).inserted }.prefix(20).map { $0 } }
        let price = object["price"] as? String ?? ""
        let sku = object["sku"] as? String ?? ""
        var warnings: [String] = []
        if price.range(of: "定金|订金|尾款|券后|起|[-–~～]", options: .regularExpression) != nil || (try? OrderImportSource.money(price)) == nil { warnings.append("网页价格含区间、促销或阶段含义，请手动核对参考价") }
        if sku.isEmpty { warnings.append("网页未确认具体颜色尺码，请逐件选择并确认规格") }
        return ProductCandidate(publicURL: canonical, name: name, properties: String((object["properties"] as? String ?? "").prefix(10000)), selectedSKU: String(sku.prefix(1000)), priceText: price, photoURLs: images("photos"), detailURLs: images("details"), warnings: warnings)
    }
    // Read bounded visible product elements only. Do not serialize page state, cookies or login data.
    static let script = #"""
    JSON.stringify((()=>{
      const visible=e=>e&&e.getClientRects().length>0;
      const text=s=>Array.from(document.querySelectorAll(s)).filter(visible).map(e=>e.textContent.trim()).filter(Boolean);
      const meta=document.querySelector('meta[property="og:title"]');
      const title=text('h1,[class^="mainTitle--"],[class^="ItemTitle--"]')[0]||(meta&&meta.content)||'';
      const sku=Array.from(document.querySelectorAll('[aria-label]')).filter(visible).map(e=>e.getAttribute('aria-label')).filter(v=>v.startsWith('已选中 ')||v.startsWith('已选“')).join('、');
      const price=text('[class^="priceText--"],[class^="Price--"]')[0]||'';
      const image=(root)=>Array.from(document.querySelectorAll(root)).filter(visible).flatMap(e=>Array.from(e.querySelectorAll('img'))).map(i=>i.getAttribute('data-src')||i.getAttribute('data-original')||i.currentSrc||i.src).filter(Boolean);
      const photos=image('[class^="PicGallery--"],[class^="mainPic--"],[class^="BasicContent--"]');
      const og=document.querySelector('meta[property="og:image"]');if(!photos.length&&og)photos.push(og.content);
      const roots=Array.from(document.querySelectorAll('#v6_pc_content,.detail-desc'));
      const detailStatus=roots.length>0&&roots.some(e=>e.innerText.trim().length>0||e.querySelector('img'))?'complete':'pending';
      return {url:location.href,detailStatus,name:title,sku,price,properties:text('[class^="Attrs--"],[class^="attributes--"],.attributes-list').join('\n'),photos,details:image('#v6_pc_content,.detail-desc')};
    })())
    """#
}
