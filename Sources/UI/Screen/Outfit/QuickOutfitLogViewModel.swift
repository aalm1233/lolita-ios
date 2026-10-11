import SwiftUI
@preconcurrency import GRDB
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class QuickOutfitLogViewModel: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var existingLogId: Int64?
    @Published var note = ""
    @Published var imageUrls: [String] = []
    @Published var selectedItemIds: Set<Int64> = []
    @Published private(set) var allItems: [Item] = []

    private let db: DatabaseQueue
    private let repo: OutfitLogRepository
    private let itemRepo: ItemRepository
    private let calendar: Calendar
    private let now: () -> Date
    private var originalImageUrls: [String] = []
    private var originalState: [String]?
    private var discardRequested = false

    private var formState: [String] {
        [note, imageUrls.joined(separator: "|"), selectedItemIds.sorted().map(String.init).joined(separator: "|")]
    }
    var hasLoaded: Bool { originalState != nil }
    var hasChanges: Bool {
        originalState.map { $0 != formState } ?? (!note.isEmpty || !imageUrls.isEmpty || !selectedItemIds.isEmpty)
    }
    var ownedItems: [Item] { allItems.filter { $0.status == .owned } }
    var selectedItems: [Item] { allItems.filter { selectedItemIds.contains($0.id) } }

    init(db: DatabaseQueue = AppModule.shared.db.dbQueue,
         calendar: Calendar = .current, now: @escaping () -> Date = { Date() }) {
        self.db = db
        repo = OutfitLogRepository(db: db)
        itemRepo = ItemRepository(db: db)
        self.calendar = calendar
        self.now = now
    }

    func load() async throws {
        // Native photo/item sheets may restart the view task. Keep in-progress edits.
        guard !hasLoaded, !isLoading, !isSaving else { return }
        isLoading = true
        defer { isLoading = false }
        let requestedDay = now()
        let items = try await itemRepo.getAll()
        try Task.checkCancellation()
        let today = try await repo.getForDay(containing: requestedDay, calendar: calendar)
        try Task.checkCancellation()
        allItems = items
        existingLogId = today?.log.id
        note = today?.log.note ?? ""
        imageUrls = today?.log.imageUrls.values ?? []
        selectedItemIds = Set(today?.itemIds ?? [])
        originalImageUrls = imageUrls
        originalState = formState
    }

    func save() async throws {
        guard !isSaving else { throw ValidationError.invalid("正在保存，请稍候") }
        guard hasLoaded else { throw ValidationError.invalid("穿搭记录尚未加载，请稍后重试") }
        guard !selectedItemIds.isEmpty else { throw ValidationError.invalid("请至少选择一件服饰") }
        isSaving = true
        defer {
            isSaving = false
            if discardRequested { discardRequested = false; discardImages() }
        }
        let committedState = formState
        let saved = try await repo.saveForDay(
            containing: now(), calendar: calendar, preferredLogId: existingLogId,
            note: note, imageUrls: imageUrls, itemIds: Array(selectedItemIds)
        )
        existingLogId = saved.id
        originalImageUrls = saved.imageUrls.values
        originalState = committedState
    }

    func toggleItem(_ id: Int64) {
        guard !isSaving, !isLoading else { return }
        if selectedItemIds.contains(id) { selectedItemIds.remove(id) }
        else { selectedItemIds.insert(id) }
    }

    func addImageData(_ data: Data) {
        guard !isSaving else { return }
        #if canImport(UIKit)
        guard let image = UIImage(data: data), let path = ImageFileHelper.save(image: image) else { return }
        #else
        guard let path = ImageFileHelper.save(imageData: data) else { return }
        #endif
        imageUrls.append(path)
    }

    func removeImage(at index: Int) {
        guard !isSaving, imageUrls.indices.contains(index) else { return }
        let path = imageUrls.remove(at: index)
        if !originalImageUrls.contains(path), !imageUrls.contains(path) {
            try? ImageFileHelper.deleteUnreferenced(paths: [path], db: db)
        }
    }

    func discardImages() {
        guard !isSaving else { discardRequested = true; return }
        let added = Set(imageUrls).subtracting(originalImageUrls)
        try? ImageFileHelper.deleteUnreferenced(paths: Array(added), db: db)
    }
}
