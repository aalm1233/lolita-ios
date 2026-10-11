import SwiftUI

@MainActor
final class CoordinateDetailViewModel: ObservableObject {
    @Published private(set) var coordinate: Coordinate?
    @Published private(set) var items: [Item] = []
    @Published private(set) var totalPrice: Double = 0
    @Published var showEdit = false

    private let coordinateRepo = AppModule.shared.coordinateRepository
    private let itemRepo = AppModule.shared.itemRepository

    func load(coordinateId: Int64) {
        Task {
            self.coordinate = try? await coordinateRepo.getById(coordinateId)
        }
        Task {
            self.items = (try? await itemRepo.getByCoordinate(coordinateId)) ?? []
            self.totalPrice = (try? await AppModule.shared.priceRepository.getTotalByCoordinate(coordinateId)) ?? 0
        }
    }

    var imageUrls: [URL] {
        coordinate?.imageUrls.values.compactMap { path in
            path.isEmpty ? nil : ImageFileHelper.fileURL(for: path)
        } ?? []
    }

    func delete() async throws {
        guard let coordinate else { return }
        try await coordinateRepo.delete(coordinate)
    }
}
