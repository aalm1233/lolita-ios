import SwiftUI

@MainActor
final class CoordinateListViewModel: ObservableObject {
    @Published private(set) var coordinates: [Coordinate] = []
    nonisolated(unsafe) private let repo = AppModule.shared.coordinateRepository

    func load() {
        Task {
            for await coords in repo.observeAll() { self.coordinates = coords }
        }
    }

    func delete(_ coordinate: Coordinate) async throws {
        try await repo.delete(coordinate)
    }
}
