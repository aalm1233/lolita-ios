import SwiftUI
import CoreGraphics
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Generated from the current Android drawing functions; each layer keeps its real clip geometry.
struct SkinVectorLibrary: Decodable, Sendable {
    struct Command: Decodable, Sendable {
        let operation: String
        let values: [Double]
        init(from decoder: Decoder) throws {
            var array = try decoder.unkeyedContainer()
            operation = try array.decode(String.self)
            var numbers: [Double] = []
            while !array.isAtEnd { numbers.append(try array.decode(Double.self)) }
            let sizes = ["M": 2, "L": 2, "Q": 4, "C": 6, "Z": 0]
            guard sizes[operation] == numbers.count, numbers.allSatisfy(\.isFinite) else {
                throw DecodingError.dataCorruptedError(in: array, debugDescription: "Invalid icon path")
            }
            values = numbers
        }
    }
    struct Clip: Decodable, Sendable { let path: [Command]; let inverse: Bool }
    struct Stroke: Decodable, Sendable { let width: Double; let cap: String; let join: String }
    struct Layer: Decodable, Sendable { let path: [Command]; let clips: [Clip]; let stroke: Stroke? }
    let styles: [String: [String: [Layer]]]

    init(from decoder: Decoder) throws { styles = try [String: [String: [Layer]]](from: decoder) }

    static let shared: Self? = {
        guard let url = SkinResources.bundle.url(forResource: "skin-icons", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }()

    func layers(key: String, skin: SkinType) -> [Layer]? { styles[skin == .default ? "SWEET" : skin.rawValue]?[key] }

    static func path(_ commands: [Command]) -> CGPath {
        let path = CGMutablePath()
        for command in commands {
            let v = command.values
            switch command.operation {
            case "M": path.move(to: CGPoint(x: v[0], y: v[1]))
            case "L": path.addLine(to: CGPoint(x: v[0], y: v[1]))
            case "Q": path.addQuadCurve(to: CGPoint(x: v[2], y: v[3]), control: CGPoint(x: v[0], y: v[1]))
            case "C": path.addCurve(to: CGPoint(x: v[4], y: v[5]), control1: CGPoint(x: v[0], y: v[1]), control2: CGPoint(x: v[2], y: v[3]))
            case "Z": path.closeSubpath()
            default: break
            }
        }
        return path
    }
}

@MainActor
enum SkinImages {
    private static var cache: [String: CGImage] = [:]

    static func raster(key: String, skin: SkinType, pixels: Int = 96) -> CGImage? {
        let cacheKey = "\(skin.rawValue)-\(key)-\(pixels)"
        if let cached = cache[cacheKey] { return cached }
        guard let layers = SkinVectorLibrary.shared?.layers(key: key, skin: skin),
              let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: CGFloat(pixels) / 24, y: CGFloat(pixels) / 24)
        context.translateBy(x: 0, y: 24)
        context.scaleBy(x: 1, y: -1) // Android paths use a top-left origin; bitmap contexts use bottom-left.
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.setStrokeColor(CGColor(gray: 0, alpha: 1))
        for layer in layers {
            context.saveGState()
            for clip in layer.clips {
                if clip.inverse {
                    context.addRect(CGRect(x: 0, y: 0, width: 24, height: 24))
                    context.addPath(SkinVectorLibrary.path(clip.path))
                    context.clip(using: .evenOdd)
                } else { context.addPath(SkinVectorLibrary.path(clip.path)); context.clip() }
            }
            context.addPath(SkinVectorLibrary.path(layer.path))
            if let stroke = layer.stroke {
                context.setLineWidth(stroke.width)
                context.setLineCap(stroke.cap == "square" ? .square : .round)
                context.setLineJoin(stroke.join == "miter" ? .miter : .round)
                context.strokePath()
            } else { context.fillPath() }
            context.restoreGState()
        }
        guard let image = context.makeImage() else { return nil }
        cache[cacheKey] = image
        return image
    }

    static func image(key: String, skin: SkinType, size: CGFloat = 24) -> Image {
        guard let cgImage = raster(key: key, skin: skin) else { return Image(systemName: "questionmark.circle") }
        #if os(iOS)
        return Image(uiImage: UIImage(cgImage: cgImage, scale: CGFloat(cgImage.width) / size, orientation: .up).withRenderingMode(.alwaysTemplate)).renderingMode(.template)
        #else
        let native = NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
        native.isTemplate = true
        return Image(nsImage: native).renderingMode(.template)
        #endif
    }

    static func image(systemName: String, skin: SkinType, size: CGFloat = 17) -> Image {
        if let key = key(for: systemName) { return image(key: key, skin: skin, size: size) }
        return Image(systemName: systemName)
    }

    static func key(for symbol: String) -> String? {
        switch symbol {
        case "house", "house.fill": "Home"
        case "heart", "heart.fill": "Wishlist"
        case "tshirt", "tshirt.fill", "hanger", "figure.stand", "figure.dress.line.vertical.figure", "square.stack", "square.stack.fill": "Outfit"
        case "chart.bar", "chart.bar.fill", "chart.bar.xaxis", "chart.pie", "chart.xyaxis.line": "Stats"
        case "gearshape", "gearshape.fill": "Settings"
        case "plus", "plus.circle", "plus.circle.fill": "Add"
        case "trash", "trash.fill": "Delete"
        case "pencil", "square.and.pencil": "Edit"
        case "magnifyingglass": "Search"
        case "arrow.up.arrow.down", "arrow.up.arrow.down.circle": "Sort"
        case "square.and.arrow.down", "checkmark": "Save"
        case "xmark", "xmark.circle", "xmark.circle.fill": "Close"
        case "square.and.arrow.up": "Share"
        case "line.3.horizontal.decrease.circle", "line.3.horizontal.decrease.circle.fill": "FilterList"
        case "ellipsis", "ellipsis.circle": "MoreVert"
        case "doc.on.doc": "ContentCopy"
        case "arrow.clockwise", "arrow.counterclockwise": "Refresh"
        case "list.bullet", "list.bullet.rectangle", "rectangle.grid.1x2": "ViewAgenda"
        case "square.grid.2x2", "square.grid.2x2.fill": "GridView"
        case "square.grid.3x3", "square.grid.3x3.fill": "Apps"
        case "rectangle.stack", "rectangle.stack.fill", "photo.on.rectangle", "photo.on.rectangle.angled": "Gallery"
        case "star.fill": "Star"
        case "star": "StarBorder"
        case "photo", "photo.fill": "Image"
        case "camera", "camera.fill": "Camera"
        case "photo.badge.plus": "AddPhoto"
        case "link": "Link"
        case "link.badge.plus": "Link"
        case "link.badge.minus": "LinkOff"
        case "paintpalette", "paintpalette.fill": "Palette"
        case "doc", "doc.fill", "doc.badge.plus", "square.and.arrow.down.on.square", "externaldrive": "FileOpen"
        case "calendar", "calendar.badge.clock": "CalendarMonth"
        case "bell", "bell.fill", "bell.badge": "Notifications"
        case "yensign.circle", "yensign.circle.fill", "yensign", "creditcard", "creditcard.fill": "AttachMoney"
        case "tag", "tag.fill": "Category"
        case "archivebox", "archivebox.fill", "mappin.and.ellipse", "mappin": "Location"
        case "arrow.left": "ArrowBack"
        case "arrow.right": "ArrowForward"
        case "chevron.left": "KeyboardArrowLeft"
        case "chevron.right": "KeyboardArrowRight"
        case "chevron.down": "ExpandMore"
        case "chevron.up": "ExpandLess"
        case "arrowtriangle.down.fill": "ArrowDropDown"
        case "arrow.up.arrow.down.square": "SwapVert"
        case "arrow.up.right.square", "arrow.up.left.and.arrow.down.right": "OpenInNew"
        case "checkmark.circle", "checkmark.circle.fill": "CheckCircle"
        case "exclamationmark.triangle", "exclamationmark.bubble": "Warning"
        case "exclamationmark.circle": "Error"
        case "info.circle": "Info"
        case "eye", "eye.fill": "Visibility"
        case "eye.slash", "eye.slash.fill": "VisibilityOff"
        case "questionmark.circle": "Help"
        case "flask", "flask.fill", "testtube.2": "Laboratory"
        default: nil // System-only concepts retain their familiar platform symbol.
        }
    }
}

struct SkinIcon: View {
    @EnvironmentObject private var skinManager: SkinManager
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 20
    let systemName: String
    var type: SkinType?

    init(systemName: String, size: CGFloat = 20, type: SkinType? = nil) {
        self.systemName = systemName
        self.type = type
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
    }
    var body: some View {
        Group {
            if let key = SkinImages.key(for: systemName) {
                SkinImages.image(key: key, skin: type ?? skinManager.currentSkinType, size: size)
                    .resizable().scaledToFit()
            } else { Image(systemName: systemName).resizable().scaledToFit() }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Keep a real Image directly inside Label: UIKit menus cannot serialize a wrapped icon view.
struct SkinLabel: View {
    let title: String
    let systemImage: String
    nonisolated init(_ title: String, systemImage: String) { self.title = title; self.systemImage = systemImage }
    var body: some View { SkinLabelContent(title: title, systemImage: systemImage) }
}

private struct SkinLabelContent: View {
    @EnvironmentObject private var skinManager: SkinManager
    let title: String
    let systemImage: String
    var body: some View {
        Label { Text(title) } icon: { SkinImages.image(systemName: systemImage, skin: skinManager.currentSkinType) }
    }
}

struct SkinButton: View {
    @EnvironmentObject private var skinManager: SkinManager
    let title: String
    let systemImage: String
    var role: ButtonRole?
    let action: () -> Void
    init(_ title: String, systemImage: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title; self.systemImage = systemImage; self.role = role; self.action = action
    }
    var body: some View {
        Button(role: role, action: action) {
            Label { Text(title) } icon: { SkinImages.image(systemName: systemImage, skin: skinManager.currentSkinType) }
        }
    }
}
