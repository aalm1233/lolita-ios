import SwiftUI
@preconcurrency import GRDB

@MainActor
final class OutfitLogEditViewModel: ObservableObject {
    @Published var date: Date = Date()
    @Published var note: String = ""
    @Published var imageUrls: [String] = []
    @Published var allItems: [Item] = []
    @Published var selectedItemIds: Set<Int64> = []
    @Published var isSaving = false

    private let db: DatabaseQueue
    private let repo: OutfitLogRepository
    private let itemRepo: ItemRepository
    private var logId: Int64?
    private var originalImageUrls: [String] = []
    private var originalState: [String]?
    private var formState: [String] { [String(date.timeIntervalSince1970), note, imageUrls.joined(separator: "|"), selectedItemIds.sorted().map(String.init).joined(separator: "|")] }
    var hasChanges: Bool { originalState.map { $0 != formState } ?? false }

    init(db: DatabaseQueue = AppModule.shared.db.dbQueue) {
        self.db = db
        repo = OutfitLogRepository(db: db)
        itemRepo = ItemRepository(db: db)
    }

    func load(logId: Int64) async {
        let requestedId: Int64? = logId > 0 ? logId : nil
        guard originalState == nil || self.logId != requestedId else { return }
        guard !Task.isCancelled else { return }
        originalState = nil
        self.logId = requestedId
        let items = (try? await itemRepo.getAll()) ?? []
        guard !Task.isCancelled else { return }
        let itemIds = Set((try? await repo.getItemIds(for: logId)) ?? [])
        guard !Task.isCancelled else { return }
        guard let log = try? await repo.getById(logId), !Task.isCancelled else { return }
        allItems = items
        selectedItemIds = itemIds
        date = Date(timeIntervalSince1970: TimeInterval(log.date) / 1000)
        note = log.note
        imageUrls = log.imageUrls.values
        originalImageUrls = log.imageUrls.values
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
        guard let logId else { throw ValidationError.invalid("穿搭记录尚未加载") }
        isSaving = true
        defer { isSaving = false }

        let committedState = formState
        let previousImages = originalImageUrls
        let committedDate = Int64(date.timeIntervalSince1970 * 1000)
        let committedNote = note
        let committedImages = imageUrls
        let committedItemIds = Array(selectedItemIds)
        guard var log = try await repo.getById(logId) else { throw ValidationError.invalid("穿搭记录已被删除") }
        log.date = committedDate
        log.note = committedNote
        log.imageUrls = StringList(committedImages)
        let saved = try await repo.save(log, itemIds: committedItemIds)

        let removed = Set(previousImages).subtracting(Set(saved.imageUrls.values))
        if !removed.isEmpty {
            try? ImageFileHelper.deleteUnreferenced(paths: Array(removed), db: db)
        }
        originalImageUrls = saved.imageUrls.values
        originalState = committedState
    }

    func discardImages() {
        guard !isSaving else { return }
        ImageFileHelper.delete(paths: Array(Set(imageUrls).subtracting(originalImageUrls)))
    }

    func toggleItem(_ id: Int64) {
        guard !isSaving else { return }
        if selectedItemIds.contains(id) { selectedItemIds.remove(id) }
        else { selectedItemIds.insert(id) }
    }
}
