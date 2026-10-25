import Foundation

/// Only these public presentation fields can reach the share renderer.
struct ShareCardContent: Codable, Sendable {
    struct Entry: Codable, Sendable {
        let name: String
        let brand: String?
        let image: String?
    }
    let title: String
    let images: [String]
    let items: [Entry]
    init(title: String, images: [String], items: [Item], brands: [Int64: String], showBrands: Bool) {
        self.title = title
        self.images = Array(images.filter { !$0.isEmpty }.prefix(3))
        self.items = items.map { Entry(name: $0.name, brand: showBrands ? brands[$0.brandId] : nil, image: $0.imageUrls.values.first) }
    }
    var pages: [[Entry]] {
        guard !items.isEmpty else { return [[]] }
        return stride(from: 0, to: items.count, by: 6).map { Array(items[$0..<min($0 + 6, items.count)]) }
    }
}
