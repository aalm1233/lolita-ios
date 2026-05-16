import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class QuickOutfitLogViewModel: ObservableObject {
    @Published var note: String = ""
    @Published var imageUrls: [String] = []
    #if canImport(UIKit)
    @Published var newImage: UIImage? = nil
    #endif
    @Published var selectedItemIds: Set<Int64> = []
    @Published var allItems: [Item] = []

    nonisolated(unsafe) private let repo = AppModule.shared.outfitLogRepository
    nonisolated(unsafe) private let itemRepo = AppModule.shared.itemRepository

    var ownedItems: [Item] {
        allItems.filter { $0.status == .owned }
    }

    func loadItems() {
        Task {
            self.allItems = (try? await itemRepo.getAll()) ?? []
        }
    }

    func save() async throws {
        #if canImport(UIKit)
        if let img = newImage, let data = img.jpegData(compressionQuality: 0.9), let path = ImageFileHelper.save(imageData: data) {
            imageUrls.append(path)
        }
        #endif
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        var log = OutfitLog(date: now, note: note, imageUrls: StringList(imageUrls), createdAt: now, updatedAt: now)
        log = try await repo.insert(log)
        if !selectedItemIds.isEmpty {
            try await repo.setItems(outfitLogId: log.id, itemIds: Array(selectedItemIds))
        }
    }
}
