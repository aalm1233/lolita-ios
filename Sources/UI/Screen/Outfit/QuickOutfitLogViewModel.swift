import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class QuickOutfitLogViewModel: ObservableObject {
    @Published var isSaving = false
    @Published var note: String = ""
    @Published var imageUrls: [String] = []
    #if canImport(UIKit)
    @Published var newImage: UIImage? = nil
    #endif
    @Published var selectedItemIds: Set<Int64> = []
    @Published var allItems: [Item] = []

    private let repo = AppModule.shared.outfitLogRepository
    private let itemRepo = AppModule.shared.itemRepository

    var ownedItems: [Item] {
        allItems.filter { $0.status == .owned }
    }

    func loadItems() {
        Task {
            self.allItems = (try? await itemRepo.getAll()) ?? []
        }
    }

    func save() async throws {
        guard !isSaving else { throw ValidationError.invalid("正在保存，请稍候") }
        isSaving = true
        defer { isSaving = false }
        #if canImport(UIKit)
        if let img = newImage, let data = img.jpegData(compressionQuality: 0.9), let path = ImageFileHelper.save(imageData: data) {
            imageUrls.append(path)
            newImage = nil
        }
        #endif
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let log = OutfitLog(date: now, note: note, imageUrls: StringList(imageUrls), createdAt: now, updatedAt: now)
        _ = try await repo.save(log, itemIds: Array(selectedItemIds))
        imageUrls = []
    }

    func discardImages() { ImageFileHelper.delete(paths: imageUrls) }
}
