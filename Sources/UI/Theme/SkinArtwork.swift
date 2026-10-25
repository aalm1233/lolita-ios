import SwiftUI
import CoreImage
import ImageIO

/// Bundled decoration never enters the user's image directory or backup payload.
enum SkinResources {
    static var bundle: Bundle {
        #if SWIFT_PACKAGE
        .module
        #else
        .main
        #endif
    }
}

struct SkinArtConfiguration: Sendable {
    let name: String
    let lightOpacity: Double
    let darkOpacity: Double
    let darkInk: (Double, Double, Double)

    static func configuration(for type: SkinType) -> Self {
        switch type {
        case .default: .init(name: "sweet", lightOpacity: 0.28, darkOpacity: 0.22, darkInk: (224, 186, 198))
        case .gothic: .init(name: "gothic", lightOpacity: 0.26, darkOpacity: 0.22, darkInk: (200, 189, 217))
        case .chinese: .init(name: "chinese", lightOpacity: 0.14, darkOpacity: 0.12, darkInk: (224, 186, 175))
        case .classic: .init(name: "classic", lightOpacity: 0.28, darkOpacity: 0.22, darkInk: (210, 193, 169))
        case .navy: .init(name: "navy", lightOpacity: 0.28, darkOpacity: 0.22, darkInk: (183, 206, 218))
        case .country: .init(name: "country", lightOpacity: 0.30, darkOpacity: 0.22, darkInk: (198, 208, 174))
        case .victorian: .init(name: "victorian", lightOpacity: 0.26, darkOpacity: 0.22, darkInk: (215, 193, 155))
        }
    }
}

@MainActor
enum SkinArtwork {
    // Limit retained full-size images when cycling skins; these are immutable bundle assets.
    private static let cache: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    static func image(for type: SkinType, dark: Bool) -> CGImage? {
        let config = SkinArtConfiguration.configuration(for: type)
        let key = "\(config.name)-\(dark)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let url = SkinResources.bundle.url(forResource: "bg_art_\(config.name)", withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let original = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let result: CGImage
        if dark {
            // Match Android's luminance matrix: retain folds and original transparent pixels.
            let (r, g, b) = config.darkInk
            func row(_ channel: Double) -> CIVector {
                let scale = channel / 255 * 0.65
                return CIVector(x: scale * 0.2126, y: scale * 0.7152, z: scale * 0.0722, w: 0)
            }
            let input = CIImage(cgImage: original)
            let filtered = input.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": row(r), "inputGVector": row(g), "inputBVector": row(b),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: r / 255 * 0.35, y: g / 255 * 0.35, z: b / 255 * 0.35, w: 0)
            ])
            guard let shaded = context.createCGImage(filtered, from: input.extent) else { return nil }
            result = shaded
        } else { result = original }
        cache.setObject(result, forKey: key, cost: result.bytesPerRow * result.height)
        return result
    }
}

/// One stationary backdrop per presented screen, outside its scrolling content.
struct SkinArtBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var skinManager: SkinManager
    var type: SkinType? = nil

    var body: some View {
        let resolved = type ?? skinManager.currentSkinType
        let skin = type.map(SkinManager.create) ?? skinManager.current
        let dark = colorScheme == .dark
        let config = SkinArtConfiguration.configuration(for: resolved)
        GeometryReader { geometry in
            ZStack {
                dark ? skin.backgroundColorDark : skin.backgroundColor
                if let cgImage = SkinArtwork.image(for: resolved, dark: dark) {
                    Image(decorative: cgImage, scale: 1)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .opacity(dark ? config.darkOpacity : config.lightOpacity)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct SkinTopBarBackground: View {
    @EnvironmentObject private var skinManager: SkinManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let skin = skinManager.current
        ZStack(alignment: .trailing) {
            if skin.topBarBlurEnabled && !reduceTransparency { Rectangle().fill(.ultraThinMaterial) }
            LinearGradient(colors: colorScheme == .dark ? skin.gradientColorsDark : skin.gradientColors,
                           startPoint: .leading, endPoint: .trailing)
                .opacity(skin.topBarBlurEnabled && !reduceTransparency ? 0.18 : 0.12)

        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// An ornament sits beside the title rather than behind tappable controls.
struct SkinBarOrnament: View {
    @EnvironmentObject private var skinManager: SkinManager
    var body: some View {
        Text(skinManager.current.topBarDecoration)
            .font(.caption)
            .foregroundStyle(.secondary)
            .opacity(skinManager.current.topBarDecorationAlpha)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
