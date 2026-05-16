import SwiftUI

@MainActor
final class ItemEditViewModel: ObservableObject {
    @Published var name: String = ""
    @Published var description: String = ""
    @Published var status: ItemStatus = .owned
    @Published var priority: ItemPriority = .medium
    @Published var brandId: Int64 = 0
    @Published var categoryId: Int64 = 0
    @Published var style: String = ""
    @Published var season: String = ""
    @Published var size: String = ""
    @Published var locationId: Int64? = nil
    @Published var imageUrls: [String] = []
    @Published var isSaving = false
    @Published var brands: [Brand] = []
    @Published var categories: [Category] = []
    @Published var locations: [Location] = []

    private let brandRepo = AppModule.shared.brandRepository
    private let categoryRepo = AppModule.shared.categoryRepository
    nonisolated(unsafe) private let itemRepo = AppModule.shared.itemRepository
    nonisolated(unsafe) private let locationRepo = AppModule.shared.locationRepository
    private var itemId: Int64?
    private var originalImageUrls: [String] = []

    func load(itemId: Int64) async {
        self.itemId = itemId
        async let brandsTask = brandRepo.getAll()
        async let categoriesTask = categoryRepo.getAll()
        async let locationsTask = locationRepo.getAll()
        brands = (try? await brandsTask) ?? []
        categories = (try? await categoriesTask) ?? []
        locations = (try? await locationsTask) ?? []

        guard let item = try? await itemRepo.getById(itemId) else { return }
        name = item.name
        description = item.description
        status = item.status
        priority = item.priority
        brandId = item.brandId
        categoryId = item.categoryId
        style = item.style ?? ""
        season = item.season ?? ""
        size = item.size ?? ""
        locationId = item.locationId
        imageUrls = item.imageUrls.values
        originalImageUrls = item.imageUrls.values
    }

    func addImageData(_ data: Data) {
        #if canImport(UIKit)
        guard let uiImage = UIImage(data: data),
              let path = ImageFileHelper.save(image: uiImage) else { return }
        #else
        guard let path = ImageFileHelper.save(imageData: data) else { return }
        #endif
        imageUrls.append(path)
    }

    func removeImage(at index: Int) {
        guard index < imageUrls.count else { return }
        let path = imageUrls[index]
        if !originalImageUrls.contains(path) {
            ImageFileHelper.delete(path: path)
        }
        imageUrls.remove(at: index)
    }

    func save() async throws {
        guard let itemId else { return }
        isSaving = true
        defer { isSaving = false }

        guard var item = try await itemRepo.getById(itemId) else { return }
        item.name = name
        item.description = description
        item.status = status
        item.priority = priority
        item.brandId = brandId
        item.categoryId = categoryId
        item.style = style.isEmpty ? nil : style
        item.season = season.isEmpty ? nil : season
        item.size = size.isEmpty ? nil : size
        item.locationId = locationId
        item.imageUrls = StringList(imageUrls)

        try await itemRepo.update(item)

        let removed = Set(originalImageUrls).subtracting(Set(imageUrls))
        if !removed.isEmpty {
            ImageFileHelper.delete(paths: Array(removed))
        }
    }
}
