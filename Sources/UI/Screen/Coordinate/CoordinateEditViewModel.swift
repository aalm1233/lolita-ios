import SwiftUI
@preconcurrency import GRDB

@MainActor
final class CoordinateEditViewModel: ObservableObject {
    @Published var name: String = ""
    @Published var description: String = ""
    @Published var imageUrls: [String] = []
    @Published var allItems: [Item] = []
    @Published var selectedItemIds: [Int64] = []
    @Published var isSaving = false

    private let db: DatabaseQueue
    private let coordinateRepo: CoordinateRepository
    private let itemRepo: ItemRepository
    private var coordinateId: Int64?
    private var originalImageUrls: [String] = []
    private var originalState: [String]?
    private var formState: [String] { [name, description, imageUrls.joined(separator: "|"), selectedItemIds.map(String.init).joined(separator: "|")] }
    var hasChanges: Bool { originalState.map { $0 != formState } ?? false }

    init(db: DatabaseQueue = AppModule.shared.db.dbQueue) {
        self.db = db
        coordinateRepo = CoordinateRepository(db: db)
        itemRepo = ItemRepository(db: db)
    }

    func load(coordinateId: Int64) async {
        let requestedId: Int64? = coordinateId > 0 ? coordinateId : nil
        guard originalState == nil || self.coordinateId != requestedId else { return }
        guard !Task.isCancelled else { return }
        originalState = nil
        self.coordinateId = requestedId
        let items = (try? await itemRepo.getAll()) ?? []
        guard !Task.isCancelled else { return }
        allItems = items
        guard coordinateId > 0 else { originalState = formState; return }
        let itemIds = (try? await coordinateRepo.getItems(for: coordinateId).map(\.id)) ?? []
        guard !Task.isCancelled else { return }
        guard let coordinate = try? await coordinateRepo.getById(coordinateId), !Task.isCancelled else { return }
        selectedItemIds = itemIds
        name = coordinate.name
        description = coordinate.description
        imageUrls = coordinate.imageUrls.values
        originalImageUrls = coordinate.imageUrls.values
        originalState = formState
    }

    var imageFileUrls: [URL] {
        imageUrls.compactMap { path in
            path.isEmpty ? nil : ImageFileHelper.fileURL(for: path)
        }
    }

    func addImageData(_ data: Data) {
        guard !isSaving else { return }
        #if canImport(UIKit)
        guard let uiImage = UIImage(data: data),
              let path = ImageFileHelper.save(image: uiImage) else { return }
        #else
        guard let path = ImageFileHelper.save(imageData: data) else { return }
        #endif
        self.imageUrls.append(path)
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

        let committedState = formState
        let previousImages = originalImageUrls
        let committedItemIds = selectedItemIds
        var coordinate = Coordinate(
            name: try InputValidation.name(name),
            description: description,
            imageUrls: StringList(imageUrls)
        )
        if let coordinateId {
            guard let existing = try await coordinateRepo.getById(coordinateId) else { throw ValidationError.invalid("套装已被删除") }
            coordinate.id = existing.id
            coordinate.createdAt = existing.createdAt
        }
        let saved = try await coordinateRepo.save(coordinate, itemIds: committedItemIds)
        self.coordinateId = saved.id

        // Clean up images that were removed
        let removed = Set(previousImages).subtracting(Set(saved.imageUrls.values))
        if !removed.isEmpty {
            try? ImageFileHelper.deleteUnreferenced(paths: Array(removed), db: db)
        }
        originalImageUrls = saved.imageUrls.values
        originalState = committedState
    }

    func toggleItem(_ id: Int64) {
        guard !isSaving else { return }
        if let index = selectedItemIds.firstIndex(of: id) { selectedItemIds.remove(at: index) }
        else { selectedItemIds.append(id) }
    }

    func discardImages() {
        guard !isSaving else { return }
        ImageFileHelper.delete(paths: Array(Set(imageUrls).subtracting(originalImageUrls)))
    }
}
