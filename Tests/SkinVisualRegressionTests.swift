import XCTest
import CoreGraphics
import ImageIO
import CryptoKit
@testable import lolita

final class SkinVisualRegressionTests: XCTestCase {
    @MainActor
    func testEveryOriginalVectorIsRenderableAndNavigationStylesAreDistinct() throws {
        let library = try XCTUnwrap(SkinVectorLibrary.shared)
        XCTAssertEqual(library.styles.count, 7)
        var homes = Set<Data>()
        for type in SkinType.allCases {
            let key = type == .default ? "SWEET" : type.rawValue
            let icons = try XCTUnwrap(library.styles[key])
            XCTAssertEqual(icons.count, 52, key)
            for name in icons.keys.sorted() {
                let image = try XCTUnwrap(SkinImages.raster(key: name, skin: type), "\(key)/\(name)")
                let bytes = try XCTUnwrap(image.dataProvider?.data) as Data
                XCTAssertTrue(bytes.enumerated().contains { $0.offset % 4 == 3 && $0.element > 0 }, "\(key)/\(name) is invisible")
                if name == "Home" { homes.insert(bytes) }
                try export(image, name: "\(key)-\(name)")
            }
        }
        XCTAssertEqual(homes.count, 7, "The seven skins must use their own silhouettes")
    }

    func testSearchAndHiddenVisibilityKeepTransparentCutouts() throws {
        let library = try XCTUnwrap(SkinVectorLibrary.shared)
        for type in SkinType.allCases {
            for name in ["Search", "VisibilityOff", "AddPhoto"] {
                let layers = try XCTUnwrap(library.layers(key: name, skin: type))
                XCTAssertTrue(layers.contains { $0.clips.contains(where: \.inverse) }, "Missing transparent cutout: \(type)/\(name)")
            }
        }
    }

    @MainActor
    func testOriginalArtAndDarkShadingRetainDimensionsAndAlpha() throws {
        for type in SkinType.allCases {
            let config = SkinArtConfiguration.configuration(for: type)
            let original = try XCTUnwrap(SkinArtwork.image(for: type, dark: false))
            let dark = try XCTUnwrap(SkinArtwork.image(for: type, dark: true))
            XCTAssertEqual(original.width, dark.width)
            XCTAssertEqual(original.height, dark.height)
            let lightPixels = rgba(original), darkPixels = rgba(dark)
            XCTAssertEqual(stride(from: 3, to: lightPixels.count, by: 4).map { lightPixels[$0] }, stride(from: 3, to: darkPixels.count, by: 4).map { darkPixels[$0] })
            let visible = stride(from: 0, to: lightPixels.count, by: 4).filter { lightPixels[$0 + 3] >= 128 }
            XCTAssertGreaterThan(visible.count, 100)
            for i in visible.enumerated().filter({ $0.offset % 1000 == 0 }).map(\.element) {
                let alpha = Double(lightPixels[i + 3]) / 255
                let luminance = (0.2126 * Double(lightPixels[i]) + 0.7152 * Double(lightPixels[i + 1]) + 0.0722 * Double(lightPixels[i + 2])) / (255 * alpha)
                for (c, ink) in [config.darkInk.0, config.darkInk.1, config.darkInk.2].enumerated() {
                    XCTAssertEqual(Double(darkPixels[i + c]), ink * (0.35 + 0.65 * luminance) * alpha, accuracy: 3, "\(type) alpha \(alpha)")
                }
            }
            try export(dark, name: "art-dark-\(config.name)")
        }
    }

    func testBackgroundPNGsMatchRecordedAndroidSourcesExactly() throws {
        struct Manifest: Decodable { let background_sha256: [String: String] }
        let url = try XCTUnwrap(SkinResources.bundle.url(forResource: "source-manifest", withExtension: "json"))
        let hashes = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url)).background_sha256
        XCTAssertEqual(hashes.count, 7)
        for (name, expected) in hashes {
            let url = try XCTUnwrap(SkinResources.bundle.url(forResource: name, withExtension: nil))
            XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined(), expected)
        }
    }

    private func rgba(_ image: CGImage) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return pixels
    }

    private func export(_ image: CGImage, name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["LOLITA_VISUAL_EXPORT_DIR"] else { return }
        let folder = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(folder.appendingPathComponent(name + ".png") as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}
