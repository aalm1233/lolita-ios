import Foundation
import CryptoKit

enum OrderImportSource {
    static func fileHash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func hash(_ text: String) -> String { fileHash(Data(text.utf8)) }
    static func json<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
    static func normalized(_ text: String) -> String { text.precomposedStringWithCompatibilityMapping.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ") }
    static func publicURL(_ raw: String) -> String? {
        guard let c = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(c.scheme?.lowercased() ?? ""), c.user == nil, c.password == nil, c.port == nil,
              let host = c.host?.lowercased(), ["item.taobao.com", "detail.tmall.com", "h5.m.taobao.com", "pages-g.m.taobao.com"].contains(host),
              let id = c.queryItems?.first(where: { $0.name == "id" })?.value,
              id.range(of: "^[0-9]{1,30}$", options: .regularExpression) != nil else { return nil }
        return "https://\(host == "detail.tmall.com" ? host : "item.taobao.com")/item.htm?id=\(id)"
    }
    static func money(_ text: String) throws -> Int64 {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "^[¥￥]\\s*", with: "", options: .regularExpression)
        guard clean.range(of: "^(?:[0-9]+|[0-9]{1,3}(?:,[0-9]{3})+)(?:\\.[0-9]{1,2})?$", options: .regularExpression) != nil,
              let value = Decimal(string: clean.replacingOccurrences(of: ",", with: ""), locale: Locale(identifier: "en_US_POSIX")), value <= Decimal(999_999_999), value >= 0 else {
            throw ValidationError.invalid("金额缺失或无效，请填写最多两位小数；未知金额不能当作零元")
        }
        return NSDecimalNumber(decimal: value * 100).int64Value
    }
    static func amount(_ cents: Int64) -> String { String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), Double(cents) / 100) }
    static func group(_ item: TaobaoOrderItem) -> String { hash([item.orderId, publicURL(item.productURL) ?? normalized(item.name), normalized(item.styleSpec)].joined(separator: "\u{1f}")) }
    private static func moneyIdentity(_ raw: String?, fallback: Double) -> String { if let cents = try? money(raw ?? String(fallback)) { return amount(cents) }; return "unknown:" + (raw ?? "") }
    static func snapshot(_ order: TaobaoOrder) -> String {
        let rows = order.items.map { [group($0), normalized($0.name), String($0.quantity), moneyIdentity($0.rawPrice, fallback: $0.price)].joined(separator: "|") }.sorted()
        return hash(([order.orderId, order.orderStatus, order.orderTime, normalized(order.shopName), moneyIdentity(order.rawPaid, fallback: order.totalPaid), moneyIdentity(order.rawShipping, fallback: order.shipping)] + rows).joined(separator: "\u{1f}"))
    }
    /// Integer largest-remainder shares are assigned before selection, in stable source order.
    static func allocate(_ total: Int64, weights: [Int64]) -> [Int64] {
        guard !weights.isEmpty else { return [] }
        let safe = weights.map { max(0, $0) }, sum = safe.reduce(0, +)
        let parts = sum > 0 ? safe : Array(repeating: 1, count: safe.count)
        let denominator = Decimal(parts.reduce(0, +))
        let exact = parts.map { Decimal(total) * Decimal($0) / denominator }
        var result = exact.map { value -> Int64 in var input = value, rounded = Decimal(); NSDecimalRound(&rounded, &input, 0, .down); return NSDecimalNumber(decimal: rounded).int64Value }
        var left = total - result.reduce(0, +)
        let indices = parts.indices.sorted { let a = exact[$0] - Decimal(result[$0]), b = exact[$1] - Decimal(result[$1]); return a == b ? $0 < $1 : a > b }
        for i in indices where left > 0 { result[i] += 1; left -= 1 }
        return result
    }
    static func units(_ order: TaobaoOrder) throws -> [TaobaoOrderItem] {
        guard order.items.allSatisfy({ (1...100).contains($0.quantity) }), order.items.reduce(0, { $0 + $1.quantity }) <= 2000 else { throw ValidationError.invalid("单行数量限 1–100，单笔订单限 2000 件，请核对") }
        var result: [TaobaoOrderItem] = [], ordinals: [String: Int] = [:]
        for item in order.items.sorted(by: { (group($0), normalized($0.name), $0.price) < (group($1), normalized($1.name), $1.price) }) {
            let g = group(item)
            for _ in 0..<item.quantity {
                var unit = item; let ordinal = ordinals[g, default: 0]; ordinals[g] = ordinal + 1
                unit.sourceKey = "taobao:v1:\(g):\(ordinal)"; unit.unitOrdinal = ordinal
                result.append(unit)
            }
        }
        return result
    }
    static func drafts(_ order: TaobaoOrder) throws -> [TaobaoImportDraft] {
        let units = try units(order)
        let shipping = try? money(order.rawShipping ?? amount(Int64((order.shipping * 100).rounded())))
        let paid = try? money(order.rawPaid ?? amount(Int64((order.totalPaid * 100).rounded())))
        let weights = units.map { (try? money($0.rawPrice ?? amount(Int64(($0.price * 100).rounded())))) ?? 0 }
        let shippingShares = allocate(shipping ?? 0, weights: Array(repeating: 1, count: units.count)), paidShares = allocate(paid ?? 0, weights: weights)
        return units.indices.map { i in
            var draft = TaobaoImportDraft(original: units[i]); draft.purchaseDate = ""; draft.sourceSnapshotHash = snapshot(order)
            draft.shippingText = shipping == nil ? "" : amount(shippingShares[i])
            draft.paidText = paid == nil ? "" : amount(paidShares[i])
            draft.priceText = (try? money(units[i].rawPrice ?? draft.priceText)) == nil ? "" : order.orderStatus == "交易成功" && paid != nil && shipping != nil && paidShares[i] >= shippingShares[i] ? amount(paidShares[i] - shippingShares[i]) : draft.priceText
            return draft
        }
    }
}
