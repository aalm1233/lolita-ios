import SwiftUI

@MainActor
final class OutfitLogEditViewModel: ObservableObject {
    @Published var date: Date = Date()
    @Published var note: String = ""
    @Published var imageUrls: [String] = []
    @Published var isSaving = false

    nonisolated(unsafe) private let repo = AppModule.shared.outfitLogRepository
    private var logId: Int64?
    private var originalImageUrls: [String] = []

    func load(logId: Int64) {
        self.logId = logId
        Task {
            guard let log = try? await repo.getById(logId) else { return }
            self.date = Date(timeIntervalSince1970: TimeInterval(log.date) / 1000)
            self.note = log.note
            self.imageUrls = log.imageUrls.values
            self.originalImageUrls = log.imageUrls.values
        }
    }

    var imageFileUrls: [URL] {
        imageUrls.compactMap { path in
            path.isEmpty ? nil : ImageFileHelper.fileURL(for: path)
        }
    }

    func addImageData(_ data: Data) {
        #if canImport(UIKit)
        guard let uiImage = UIImage(data: data),
              let path = ImageFileHelper.save(image: uiImage) else { return }
        #else
        guard let path = ImageFileHelper.save(imageData: data) else { return }
        #endif
        self.imageUrls.append(path)
    }

    func removeImage(at index: Int) {
        guard index < imageUrls.count else { return }
        let path = imageUrls[index]
        if !originalImageUrls.contains(path) {
            ImageFileHelper.delete(path: path)
        }
        imageUrls.remove(at: index)
    }

    func save() async throws {
        guard let logId else { return }
        isSaving = true
        defer { isSaving = false }

        guard var log = try await repo.getById(logId) else { return }
        log.date = Int64(date.timeIntervalSince1970 * 1000)
        log.note = note
        log.imageUrls = StringList(imageUrls)
        try await repo.update(log)

        let removed = Set(originalImageUrls).subtracting(Set(imageUrls))
        if !removed.isEmpty {
            ImageFileHelper.delete(paths: Array(removed))
        }
    }
}
