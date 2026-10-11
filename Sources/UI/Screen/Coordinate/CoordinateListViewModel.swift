import SwiftUI

@MainActor
final class CoordinateListViewModel: ObservableObject {
    @Published private(set) var coordinates: [Coordinate] = []
    private let repo = AppModule.shared.coordinateRepository

    private var observationTasks: [Task<Void, Never>] = []

    func stopObserving() {
        observationTasks.forEach { $0.cancel() }
        observationTasks.removeAll()
    }

    func load() {
        guard observationTasks.isEmpty else { return }
        observationTasks.append(Task { [weak self, repo] in
            for await coords in repo.observeAll() { guard !Task.isCancelled else { return }; self?.coordinates = coords }
        })
    }

    func delete(_ coordinate: Coordinate) async throws {
        try await repo.delete(coordinate)
    }
}
