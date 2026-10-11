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
    @Published private(set) var errorMessage: String?

    private let db: DatabaseQueue
    private let repo: OutfitLogRepository
    private let itemRepo: ItemRepository
    private var logId: Int64?
    private var originalImageUrls: [String] = []
    private var originalItemIds: Set<Int64> = []
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
        let items: [Item]
        do { items = try await itemRepo.getAll() }
        catch { errorMessage = userFacingError(error); return }
        guard !Task.isCancelled else { return }
        allItems = items
        errorMessage = nil
        if requestedId == nil {
            date = Date()
            note = ""
            imageUrls = []
            originalImageUrls = []
            selectedItemIds = []
            originalItemIds = []
            originalState = formState
            return
        }
        let itemIds = Set((try? await repo.getItemIds(for: logId)) ?? [])
        guard !Task.isCancelled else { return }
        guard let log = try? await repo.getById(logId), !Task.isCancelled else {
            if !Task.isCancelled { errorMessage = "穿搭记录已不存在" }
            return
        }
        allItems = items
        selectedItemIds = itemIds
        originalItemIds = itemIds
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
        guard originalState != nil else { throw ValidationError.invalid("穿搭记录尚未加载") }
        if logId == nil && selectedItemIds.isEmpty { throw ValidationError.invalid("请至少选择一件穿搭服饰") }
        isSaving = true
        defer { isSaving = false }

        let committedState = formState
        let previousImages = originalImageUrls
        let committedDate = Int64(date.timeIntervalSince1970 * 1000)
        let committedNote = note
        let committedImages = imageUrls
        let committedItemIds = Array(selectedItemIds)
        let newItemIds = Set(committedItemIds).subtracting(originalItemIds)
        let ownedIds = try await db.read { @Sendable db in
            Set(try Item.filter(Item.Columns.status == ItemStatus.owned).fetchAll(db).map(\.id))
        }
        guard newItemIds.isSubset(of: ownedIds) else { throw ValidationError.invalid("只能新增已拥有的穿搭服饰，请核对服饰状态") }
        var log: OutfitLog
        if let logId {
            guard let existing = try await repo.getById(logId) else { throw ValidationError.invalid("穿搭记录已被删除") }
            log = existing
        } else {
            log = OutfitLog(date: committedDate, note: committedNote)
        }
        log.date = committedDate
        log.note = committedNote
        log.imageUrls = StringList(committedImages)
        let saved = try await repo.save(log, itemIds: committedItemIds)
        logId = saved.id

        let removed = Set(previousImages).subtracting(Set(saved.imageUrls.values))
        if !removed.isEmpty {
            try? ImageFileHelper.deleteUnreferenced(paths: Array(removed), db: db)
        }
        originalImageUrls = saved.imageUrls.values
        originalItemIds = Set(committedItemIds)
        originalState = committedState
    }

    func discardImages() {
        guard !isSaving else { return }
        ImageFileHelper.delete(paths: Array(Set(imageUrls).subtracting(originalImageUrls)))
    }

    func toggleItem(_ id: Int64) {
        guard !isSaving else { return }
        if selectedItemIds.contains(id) { selectedItemIds.remove(id) }
        else if allItems.first(where: { $0.id == id })?.status == .owned { selectedItemIds.insert(id) }
    }
}
