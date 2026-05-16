import SwiftUI

@MainActor
final class OutfitLogListViewModel: ObservableObject {
    @Published private(set) var logs: [OutfitLog] = []
    nonisolated(unsafe) private let repo = AppModule.shared.outfitLogRepository

    func load() {
        Task {
            for await logs in repo.observeAll() { self.logs = logs }
        }
    }

    func delete(_ log: OutfitLog) async throws {
        try await repo.delete(log)
    }

    /// Group logs by date (day granularity)
    var groupedLogs: [(date: Date, logs: [OutfitLog])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: logs) { log -> Date in
            calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(log.date) / 1000))
        }
        return grouped.sorted { $0.key > $1.key }.map { ($0.key, $0.value) }
    }
}
