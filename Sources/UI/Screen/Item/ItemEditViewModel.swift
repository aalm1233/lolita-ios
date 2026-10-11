import SwiftUI
@preconcurrency import GRDB

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
    @Published var colors: Set<String> = []
    @Published var source: String = ""
    @Published var coordinateId: Int64? = nil
    @Published var sizeChartImageUrl: String? = nil
    @Published var styles: [Style] = []
    @Published var seasons: [Season] = []
    @Published var sources: [Source] = []
    @Published var coordinates: [Coordinate] = []
    @Published var size: String = ""
    @Published var locationId: Int64? = nil
    @Published var imageUrls: [String] = []
    @Published var isSaving = false
    @Published var brands: [Brand] = []
    @Published var categories: [Category] = []
    @Published var locations: [Location] = []

    private let db: DatabaseQueue
    private let brandRepo: BrandRepository
    private let categoryRepo: CategoryRepository
    private let itemRepo: ItemRepository
    private let locationRepo: LocationRepository
    private var itemId: Int64?
    private var originalImageUrls: [String] = []
    private var originalSizeChart: String?
    private var originalState: [String]?
    private var formState: [String] { [name, description, status.rawValue, priority.rawValue, String(brandId), String(categoryId), style, season, size, source, String(locationId ?? 0), String(coordinateId ?? 0), colors.sorted().joined(separator: "|"), imageUrls.joined(separator: "|"), sizeChartImageUrl ?? ""] }
    var hasChanges: Bool { originalState.map { $0 != formState } ?? false }

    init(db: DatabaseQueue = AppModule.shared.db.dbQueue) {
        self.db = db
        brandRepo = BrandRepository(db: db)
        categoryRepo = CategoryRepository(db: db)
        itemRepo = ItemRepository(db: db)
        locationRepo = LocationRepository(db: db)
    }

    func load(itemId: Int64, defaultStatus: ItemStatus = .owned) async {
        let requestedId: Int64? = itemId > 0 ? itemId : nil
        guard originalState == nil || self.itemId != requestedId else { return }
        guard !Task.isCancelled else { return }
        originalState = nil
        self.itemId = requestedId
        status = defaultStatus
        async let brandsTask = brandRepo.getAll()
        async let categoriesTask = categoryRepo.getAll()
        async let locationsTask = locationRepo.getAll()
        let loadedBrands = (try? await brandsTask) ?? []
        let loadedCategories = (try? await categoriesTask) ?? []
        let loadedLocations = (try? await locationsTask) ?? []
        let loadedStyles = (try? await StyleRepository(db: db).getAll()) ?? []
        let loadedSeasons = (try? await SeasonRepository(db: db).getAll()) ?? []
        let loadedSources = (try? await SourceRepository(db: db).getAll()) ?? []
        let loadedCoordinates = (try? await CoordinateRepository(db: db).getAll()) ?? []
        guard !Task.isCancelled else { return }

        brands = loadedBrands
        categories = loadedCategories
        locations = loadedLocations
        styles = loadedStyles
        seasons = loadedSeasons
        sources = loadedSources
        coordinates = loadedCoordinates
        brandId = brands.first?.id ?? 0
        categoryId = categories.first?.id ?? 0
        guard itemId > 0 else { originalState = formState; return }
        guard let item = try? await itemRepo.getById(itemId), !Task.isCancelled else { return }
        name = item.name
        description = item.description
        status = item.status
        priority = item.priority
        brandId = item.brandId
        categoryId = item.categoryId
        style = item.style ?? ""
        season = item.season ?? ""
        size = item.size ?? ""
        colors = Set(item.colors.values)
        source = item.source ?? ""
        coordinateId = item.coordinateId
        sizeChartImageUrl = item.sizeChartImageUrl
        originalSizeChart = item.sizeChartImageUrl
        locationId = item.locationId
        imageUrls = item.imageUrls.values
        originalImageUrls = item.imageUrls.values
        originalState = formState
    }

    func addImageData(_ data: Data) {
        guard !isSaving else { return }
        #if canImport(UIKit)
        guard let uiImage = UIImage(data: data),
              let path = ImageFileHelper.save(image: uiImage) else { return }
        #else
        guard let path = ImageFileHelper.save(imageData: data) else { return }
        #endif
        imageUrls.append(path)
    }

    func removeImage(at index: Int) {
        guard !isSaving, imageUrls.indices.contains(index) else { return }
        let path = imageUrls[index]
        if !originalImageUrls.contains(path) {
            ImageFileHelper.delete(path: path)
        }
        imageUrls.remove(at: index)
    }

    func save() async throws {
        guard !isSaving else { throw ValidationError.invalid("正在保存，请稍候") }
        isSaving = true
        defer { isSaving = false }

        guard brands.contains(where: { $0.id == brandId }), categories.contains(where: { $0.id == categoryId }) else {
            throw ValidationError.invalid("请选择品牌和分类")
        }
        let committedState = formState
        let previousImages = originalImageUrls
        let previousChart = originalSizeChart
        var item = Item(
            name: try InputValidation.name(name),
            brandId: brandId,
            categoryId: categoryId,
            status: status,
            priority: priority,
            description: description,
            colors: StringList(colors.sorted()),
            season: season.isEmpty ? nil : season,
            style: style.isEmpty ? nil : style,
            size: size.isEmpty ? nil : size,
            sizeChartImageUrl: sizeChartImageUrl,
            imageUrls: StringList(imageUrls),
            coordinateId: coordinateId,
            locationId: locationId,
            source: source.isEmpty ? nil : source
        )
        if let itemId {
            guard let existing = try await itemRepo.getById(itemId) else { throw ValidationError.invalid("服饰已被删除") }
            item.id = existing.id
            item.createdAt = existing.createdAt
            item.coordinateOrder = existing.coordinateOrder
        }

        if itemId != nil { try await itemRepo.update(item) }
        else { let saved = try await itemRepo.insert(item); itemId = saved.id }

        let removed = Set(previousImages).subtracting(Set(item.imageUrls.values))
        if !removed.isEmpty {
            try? ImageFileHelper.deleteUnreferenced(paths: Array(removed), db: db)
        }
        if previousChart != item.sizeChartImageUrl, let old = previousChart {
            try? ImageFileHelper.deleteUnreferenced(paths: [old], db: db)
        }
        originalImageUrls = item.imageUrls.values
        originalSizeChart = item.sizeChartImageUrl
        originalState = committedState
    }

    func setSizeChart(data: Data) {
        guard !isSaving else { return }
        guard let path = ImageFileHelper.save(imageData: data) else { return }
        if let previous = sizeChartImageUrl, previous != originalSizeChart { ImageFileHelper.delete(path: previous) }
        sizeChartImageUrl = path
    }

    func removeSizeChart() {
        guard !isSaving else { return }
        if let path = sizeChartImageUrl, path != originalSizeChart {
            ImageFileHelper.delete(path: path)
        }
        sizeChartImageUrl = nil
    }

    func discardImages() {
        guard !isSaving else { return }
        ImageFileHelper.delete(paths: Array(Set(imageUrls).subtracting(originalImageUrls)))
        if let chart = sizeChartImageUrl, chart != originalSizeChart { ImageFileHelper.delete(path: chart) }
    }
}
