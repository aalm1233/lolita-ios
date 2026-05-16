import SwiftUI

@MainActor
final class ItemDetailViewModel: ObservableObject {
    @Published private(set) var item: Item?
    @Published private(set) var brandName: String = ""
    @Published private(set) var categoryName: String = ""
    @Published private(set) var locationName: String = ""
    @Published private(set) var recommendations: [MatchScore] = []

    let itemId: Int64
    private let brandRepo = AppModule.shared.brandRepository
    private let categoryRepo = AppModule.shared.categoryRepository
    nonisolated(unsafe) private let itemRepo = AppModule.shared.itemRepository
    nonisolated(unsafe) private let locationRepo = AppModule.shared.locationRepository
    nonisolated(unsafe) private let recRepo = AppModule.shared.recommendationRepository

    init(itemId: Int64) { self.itemId = itemId }

    func load() async {
        guard let item = try? await itemRepo.getById(itemId) else { return }
        self.item = item
        if let brand = try? await brandRepo.getAll().first(where: { $0.id == item.brandId }) {
            brandName = brand.name
        }
        if let cat = try? await categoryRepo.getAll().first(where: { $0.id == item.categoryId }) {
            categoryName = cat.name
        }
        if let locId = item.locationId,
           let loc = try? await locationRepo.getAll().first(where: { $0.id == locId }) {
            locationName = loc.name
        }
        if let recs = try? await recRepo.getRecommendations(for: item) {
            recommendations = recs
        }
    }

    var imageUrls: [URL] {
        item?.imageUrls.values.compactMap {
            $0.isEmpty ? nil : ImageFileHelper.fileURL(for: $0)
        } ?? []
    }

    func deleteItem() async throws {
        guard let item else { return }
        ImageFileHelper.delete(paths: item.imageUrls.values)
        try await itemRepo.delete(item)
    }
}
