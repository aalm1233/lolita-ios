import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum ImageFileHelper {
    private static var imagesDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("images")
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Copy image data to images directory with UUID filename. Returns the stored path.
    static func save(imageData: Data) -> String? {
        let uuid = UUID().uuidString
        let url = imagesDir.appendingPathComponent("\(uuid).jpg")
        do {
            try imageData.write(to: url)
            return url.path
        } catch {
            print("ImageFileHelper: failed to save image: \(error)")
            return nil
        }
    }

    #if canImport(UIKit)
    /// Copy picked UIImage to images directory. Returns stored path.
    static func save(image: UIImage) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.9) else { return nil }
        return save(imageData: data)
    }
    #endif

    /// Delete image at stored path.
    static func delete(path: String) {
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.removeItem(at: url)
    }

    /// Delete multiple images at paths.
    static func delete(paths: [String]) {
        for path in paths { delete(path: path) }
    }

    /// Resolve stored path to URL for display.
    static func fileURL(for path: String) -> URL {
        URL(fileURLWithPath: path)
    }
}
