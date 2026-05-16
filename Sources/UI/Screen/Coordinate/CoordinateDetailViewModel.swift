import SwiftUI

@MainActor
final class CoordinateDetailViewModel: ObservableObject {
    @Published private(set) var coordinate: Coordinate?
    @Published private(set) var items: [Item] = []
    @Published var showEdit = false

    nonisolated(unsafe) private let coordinateRepo = AppModule.shared.coordinateRepository
    nonisolated(unsafe) private let itemRepo = AppModule.shared.itemRepository

    func load(coordinateId: Int64) {
        Task {
            self.coordinate = try? await coordinateRepo.getById(coordinateId)
        }
        Task {
            self.items = (try? await itemRepo.getByCoordinate(coordinateId)) ?? []
        }
    }

    var imageUrls: [URL] {
        coordinate?.imageUrls.values.compactMap { path in
            path.isEmpty ? nil : ImageFileHelper.fileURL(for: path)
        } ?? []
    }

    func delete() async throws {
        guard let coordinate else { return }
        ImageFileHelper.delete(paths: coordinate.imageUrls.values)
        try await coordinateRepo.delete(coordinate)
    }
}
