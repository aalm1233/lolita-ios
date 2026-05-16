import SwiftUI

@MainActor
final class OutfitLogDetailViewModel: ObservableObject {
    @Published private(set) var log: OutfitLog?
    @Published private(set) var items: [Item] = []

    nonisolated(unsafe) private let repo = AppModule.shared.outfitLogRepository
    nonisolated(unsafe) private let itemRepo = AppModule.shared.itemRepository

    func load(logId: Int64) {
        Task {
            self.log = try? await repo.getById(logId)
        }
        Task {
            guard let itemIds = try? await repo.getItemIds(for: logId) else { return }
            let allItems = (try? await itemRepo.getAll()) ?? []
            self.items = allItems.filter { itemIds.contains($0.id) }
        }
    }

    var imageUrls: [URL] {
        log?.imageUrls.values.compactMap { path in
            path.isEmpty ? nil : ImageFileHelper.fileURL(for: path)
        } ?? []
    }

    func delete() async throws {
        guard let log else { return }
        ImageFileHelper.delete(paths: log.imageUrls.values)
        try await repo.delete(log)
    }
}
