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
    @Published var sizeChartImageUrls: [String] = []
    @Published var composition: ItemComposition = .unconfirmed
    @Published var specifications = WardrobeSpecifications()
    @Published var storageNodeId: Int64?
    @Published private(set) var storageNodes: [StorageNode] = []
    @Published private(set) var pendingDraft: ItemDraft?
    @Published private(set) var draftMessage: String?
    private var draftKey = ""
    private var baselineUpdatedAt: Int64?
    private var draftReady = false
    private var isLeaving = false
    private var originalDetails: [String] = []
    var semantic: CategorySemantic { categories.first(where: { $0.id == categoryId })?.categorySemantic ?? .unconfirmed }
    var detailImages: [String] { var seen = Set<String>(); return ([sizeChartImageUrl].compactMap { $0 } + sizeChartImageUrls).filter { seen.insert($0).inserted } }
    @Published private(set) var registeredSizes: [String] = []
    var sizeOptions: [String] {
        var seen = Set<String>()
        return (["XS", "S", "M", "L", "XL", "XXL", "均码"] + registeredSizes + [size]).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }
    var draftState: String { formState.joined(separator: "\u{1f}") }
    @Published var isSaving = false
    @Published var brands: [Brand] = []
    @Published var categories: [Category] = []
    @Published var locations: [Location] = []
    @Published var parentItemId: Int64?
    @Published var includedInParentPrice = false
    @Published private(set) var parentCandidates: [Item] = []

    private let db: DatabaseQueue
    private let brandRepo: BrandRepository
    private let categoryRepo: CategoryRepository
    private let itemRepo: ItemRepository
    private let locationRepo: LocationRepository
    private var itemId: Int64?
    private var originalImageUrls: [String] = []
    private var originalSizeChart: String?
    private var originalState: [String]?
    private var formState: [String] { [name, description, status.rawValue, priority.rawValue, String(brandId), String(categoryId), style, season, size, source, String(locationId ?? 0), String(coordinateId ?? 0), colors.sorted().joined(separator: "|"), imageUrls.joined(separator: "|"), sizeChartImageUrl ?? "", String(parentItemId ?? 0), String(includedInParentPrice), composition.rawValue, (try? specifications.encoded()) ?? "", detailImages.joined(separator: "|"), String(storageNodeId ?? 0)] }
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
        draftKey = requestedId.map { "item.\($0)" } ?? "new.\(defaultStatus.rawValue)"
        isLeaving = false; draftReady = false
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
        storageNodes = (try? await StorageRepository(db: db).getAll()) ?? []
        let allItems = (try? await itemRepo.getAll()) ?? []
        registeredSizes = allItems.compactMap(\.size)
        parentCandidates = allItems.filter { $0.id != itemId && $0.parentItemId == nil }
        styles = loadedStyles
        seasons = loadedSeasons
        sources = loadedSources
        coordinates = loadedCoordinates
        brandId = brands.first?.id ?? 0
        categoryId = categories.first?.id ?? 0
        guard itemId > 0 else {
            originalState = formState
            pendingDraft = try? await ItemDraftRepository(db: db).get(draftKey)
            draftReady = pendingDraft == nil
            return
        }
        guard let item = try? await itemRepo.getById(itemId), !Task.isCancelled else { return }
        name = item.name
        description = item.description
        status = item.status
        parentItemId = item.parentItemId
        includedInParentPrice = item.includedInParentPrice
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
        sizeChartImageUrls = item.sizeChartImageUrls.values
        originalDetails = item.detailImagePaths
        composition = item.composition
        specifications = (try? WardrobeSpecifications.decode(item.specificationsJson)) ?? WardrobeSpecifications()
        storageNodeId = item.storageNodeId
        baselineUpdatedAt = item.updatedAt
        locationId = item.locationId
        imageUrls = item.imageUrls.values
        originalImageUrls = item.imageUrls.values
        originalState = formState
        pendingDraft = try? await ItemDraftRepository(db: db).get(draftKey)
        draftReady = pendingDraft == nil
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
        imageUrls.remove(at: index)
        if !originalImageUrls.contains(path) { try? ImageFileHelper.deleteUnreferenced(paths: [path], db: db) }
    }

    func save() async throws {
        guard !isSaving else { throw ValidationError.invalid("正在保存，请稍候") }
        isSaving = true
        defer { isSaving = false }

        guard brands.contains(where: { $0.id == brandId }), categories.contains(where: { $0.id == categoryId }) else {
            throw ValidationError.invalid("请选择品牌和分类")
        }
        let expectedUpdatedAt = baselineUpdatedAt
        let committedState = formState
        let previousImages = originalImageUrls
        let previousChart = originalSizeChart
        let previousDetails = originalDetails
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
        item.composition = composition
        item.specificationsJson = try specifications.encoded()
        item.storageNodeId = storageNodeId
        item.sizeChartImageUrls = StringList(detailImages)
        item.sizeChartImageUrl = detailImages.first
        item.parentItemId = parentItemId
        item.includedInParentPrice = includedInParentPrice
        let persistedDraftImages = draftKey.isEmpty ? [] : ((try await ItemDraftRepository(db: db).get(draftKey))?.allImagePaths ?? [])
        if let itemId {
            guard let existing = try await itemRepo.getById(itemId) else { throw ValidationError.invalid("服饰已被删除") }
            item.id = existing.id
            item.createdAt = existing.createdAt
            item.coordinateOrder = existing.coordinateOrder
            item.importOrderKeys = existing.importOrderKeys
        }

        if itemId != nil { try await itemRepo.update(item, clearingDraft: draftKey.isEmpty ? nil : draftKey, expectedUpdatedAt: expectedUpdatedAt) }
        else { let saved = try await itemRepo.insert(item, clearingDraft: draftKey.isEmpty ? nil : draftKey); itemId = saved.id }

        let removed = Set(previousImages).subtracting(Set(item.imageUrls.values))
        if !removed.isEmpty {
            try? ImageFileHelper.deleteUnreferenced(paths: Array(removed), db: db)
        }
        if previousChart != item.sizeChartImageUrl, let old = previousChart {
            try? ImageFileHelper.deleteUnreferenced(paths: [old], db: db)
        }
        try? ImageFileHelper.deleteUnreferenced(paths: previousDetails + persistedDraftImages, db: db)
        originalDetails = item.detailImagePaths
        originalImageUrls = item.imageUrls.values
        originalSizeChart = item.sizeChartImageUrl
        originalState = committedState
        isLeaving = true
    }

    func setSizeChart(data: Data) {
        guard !isSaving else { return }
        guard let path = ImageFileHelper.save(imageData: data) else { return }
        if let previous = sizeChartImageUrl, previous != originalSizeChart { try? ImageFileHelper.deleteUnreferenced(paths: [previous], db: db) }
        sizeChartImageUrl = path
        sizeChartImageUrls = []
    }

    func removeSizeChart() {
        guard !isSaving else { return }
        if let path = sizeChartImageUrl, path != originalSizeChart {
            try? ImageFileHelper.deleteUnreferenced(paths: [path], db: db)
        }
        let removed = detailImages
        sizeChartImageUrl = nil
        sizeChartImageUrls = []
        try? ImageFileHelper.deleteUnreferenced(paths: removed.filter { !originalDetails.contains($0) }, db: db)
    }

    func discardImages() {
        guard !isSaving else { return }
        try? ImageFileHelper.deleteUnreferenced(paths: Array(Set(imageUrls).subtracting(originalImageUrls)), db: db)
        if let chart = sizeChartImageUrl, chart != originalSizeChart { try? ImageFileHelper.deleteUnreferenced(paths: [chart], db: db) }
    }

    func setCover(at index: Int) {
        guard !isSaving, imageUrls.indices.contains(index) else { return }
        let path = imageUrls.remove(at: index); imageUrls.insert(path, at: 0)
    }
    func addDetailImageData(_ data: Data) {
        guard !isSaving, let path = ImageFileHelper.save(imageData: data) else { return }
        sizeChartImageUrls = detailImages + [path]; sizeChartImageUrl = sizeChartImageUrls.first
    }
    func removeDetailImage(at index: Int) {
        guard !isSaving, detailImages.indices.contains(index) else { return }
        var paths = detailImages; let removed = paths.remove(at: index)
        sizeChartImageUrls = paths; sizeChartImageUrl = paths.first
        if !originalDetails.contains(removed) { try? ImageFileHelper.deleteUnreferenced(paths: [removed], db: db) }
    }
    private func draftItem() throws -> Item {
        var item = Item(name: name, brandId: brandId, categoryId: categoryId, status: status, priority: priority,
                        description: description, colors: StringList(colors.sorted()), season: season.isEmpty ? nil : season,
                        style: style.isEmpty ? nil : style, size: size.isEmpty ? nil : size,
                        sizeChartImageUrl: detailImages.first, imageUrls: StringList(imageUrls), coordinateId: coordinateId,
                        locationId: locationId, source: source.isEmpty ? nil : source)
        item.id = itemId ?? 0; item.parentItemId = parentItemId; item.includedInParentPrice = includedInParentPrice
        item.composition = composition; item.specificationsJson = try specifications.encoded()
        item.sizeChartImageUrls = StringList(detailImages); item.storageNodeId = storageNodeId
        return item
    }
    func persistDraft() async throws {
        guard draftReady, !isSaving, !isLeaving else { return }
        if !hasChanges {
            if try await ItemDraftRepository(db: db).get(draftKey) != nil { try await ItemDraftRepository(db: db).delete(draftKey) }
            draftMessage = nil
            return
        }
        let draft = try ItemDraft.make(id: draftKey, item: draftItem(), baseline: baselineUpdatedAt)
        try await ItemDraftRepository(db: db).save(draft)
        draftMessage = "草稿已保存"
    }
    func autosaveDraft() async {
        do { try await persistDraft() }
        catch { draftMessage = "草稿保存失败：" + userFacingError(error) }
    }
    func resumeDraft() throws {
        guard let draft = pendingDraft else { return }
        let item = try draft.item()
        name = item.name; description = item.description; brandId = item.brandId; categoryId = item.categoryId
        status = item.status; priority = item.priority; style = item.style ?? ""; season = item.season ?? ""
        size = item.size ?? ""; colors = Set(item.colors.values); source = item.source ?? ""
        coordinateId = item.coordinateId; parentItemId = item.parentItemId; includedInParentPrice = item.includedInParentPrice
        imageUrls = item.imageUrls.values; sizeChartImageUrl = item.sizeChartImageUrl; sizeChartImageUrls = item.sizeChartImageUrls.values
        locationId = item.locationId; storageNodeId = item.storageNodeId; composition = item.composition
        specifications = try WardrobeSpecifications.decode(item.specificationsJson)
        baselineUpdatedAt = draft.baselineUpdatedAt
        pendingDraft = nil; draftReady = true; draftMessage = "已恢复草稿，请核对后保存"
    }
    func discardDraft() async throws {
        isLeaving = true
        try await ItemDraftRepository(db: db).delete(draftKey)
        let newImages = Set(imageUrls + detailImages).subtracting(originalImageUrls + originalDetails + [originalSizeChart].compactMap { $0 })
        try? ImageFileHelper.deleteUnreferenced(paths: Array(newImages), db: db)
        pendingDraft = nil
    }
    func rejectPendingDraft() async throws {
        try await ItemDraftRepository(db: db).delete(draftKey)
        pendingDraft = nil; draftReady = true
    }
}
