import SwiftUI
import ImageIO
#if os(iOS)
import UIKit
#else
import AppKit
#endif

@MainActor
enum ShareCardRenderer {
    static func render(_ content: ShareCardContent, skin: any SkinProtocol, dark: Bool) async throws -> [URL] {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("share-cards", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Only our generated jobs expire. Wardrobe images are read, never changed.
        for url in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey])) ?? [] {
            if let date = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate, date < Date().addingTimeInterval(-86400) { try? FileManager.default.removeItem(at: url) }
        }
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var urls: [URL] = []
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 12
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        do {
            let pages = content.pages
            for (index, entries) in pages.enumerated() {
                try Task.checkCancellation()
                let heroes = index == 0 ? content.images : []
                var images: [String: CGImage] = [:]
                for path in Set(heroes + entries.compactMap(\.image)) {
                    try Task.checkCancellation()
                    if let image = try await thumbnail(path, session: session) { images[path] = image }
                }
                let page = ShareCardPage(title: content.title, heroes: heroes, entries: entries, images: images, skin: skin, dark: dark, page: index + 1, count: pages.count)
                let renderer = ImageRenderer(content: page)
                renderer.proposedSize = ProposedViewSize(width: 540, height: nil)
                renderer.scale = 2
                #if os(iOS)
                let data = renderer.uiImage?.pngData()
                #else
                let data = renderer.nsImage?.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }
                #endif
                guard let data else { throw ValidationError.invalid("分享图片生成失败，请重新生成") }
                try Task.checkCancellation()
                let url = directory.appendingPathComponent("穿搭-\(index + 1).png")
                try data.write(to: url, options: .atomic)
                urls.append(url)
                await Task.yield()
            }
            return urls
        } catch { try? FileManager.default.removeItem(at: directory); throw error }
    }

    private static func thumbnail(_ path: String, session: URLSession) async throws -> CGImage? {
        let url = ImageFileHelper.fileURL(for: path)
        let local: URL
        if url.isFileURL { local = url }
        else {
            guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
            do {
                let (file, response) = try await session.download(for: URLRequest(url: url))
                defer { try? FileManager.default.removeItem(at: file) }
                guard (response as? HTTPURLResponse).map({ (200...299).contains($0.statusCode) }) == true else { return nil }
                return decode(file)
            } catch { try Task.checkCancellation(); return nil }
        }
        return decode(local)
    }
    private static func decode(_ url: URL) -> CGImage? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), size.isRegularFile == true, (size.fileSize ?? Int.max) <= 20_000_000,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1000, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
    }
}

private struct ShareCardPage: View {
    let title: String
    let heroes: [String]
    let entries: [ShareCardContent.Entry]
    let images: [String: CGImage]
    let skin: any SkinProtocol
    let dark: Bool
    let page: Int
    let count: Int
    private var background: Color { dark ? skin.backgroundColorDark : skin.backgroundColor }
    private var surface: Color { dark ? skin.cardColorDark : skin.cardColor }
    private var accent: Color { dark ? skin.accentColorDark : skin.accentColor }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(title.prefix(300))).font(headingFont).lineLimit(5).foregroundStyle(dark ? .white : .black)
            if !heroes.isEmpty {
                HStack(spacing: 6) { ForEach(Array(heroes.enumerated()), id: \.offset) { _, path in photo(path).frame(maxWidth: .infinity).frame(height: 280).clipped() } }
            }
            ForEach(Array(entries.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 16) {
                    photo(item.image).frame(width: 70, height: 90).clipped()
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(item.name.prefix(300))).font(.system(size: 19, weight: .medium)).lineLimit(4)
                        if let brand = item.brand { Text(String(brand.prefix(300))).font(.system(size: 15)).lineLimit(2).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(surface, in: RoundedRectangle(cornerRadius: skin.cornerRadiusM))
            }
            Rectangle().fill(accent).frame(height: 2)
            Text("我的 Lolita · 穿搭分享  \(page)/\(count)").font(.system(size: 13)).foregroundStyle(.secondary)
        }.padding(30).frame(width: 540, alignment: .leading).background(background)
            .environment(\.colorScheme, dark ? .dark : .light)
    }
    private var headingFont: Font { skin.fontName.map { .custom($0, size: 27) } ?? .system(size: 27, weight: .semibold) }
    private func photo(_ path: String?) -> some View {
        ZStack {
            surface
            if let path, let image = images[path] { Image(decorative: image, scale: 1).resizable().scaledToFit() }
            else { Text("暂无图片").font(.system(size: 13)).foregroundStyle(.secondary) }
        }
    }
}

struct ShareCardScreen: View {
    let title: String
    let images: [String]
    let items: [Item]
    let brands: [Int64: String]
    @EnvironmentObject private var skinManager: SkinManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var showBrands = true
    @State private var files: [URL] = []
    @State private var loading = true
    @State private var error: String?
    @State private var retry = 0
    @State private var sharing = false
    private var generation: String { "\(showBrands)-\(colorScheme)-\(skinManager.currentSkinType.rawValue)-\(retry)" }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Toggle("显示品牌", isOn: $showBrands).accessibilityIdentifier("share-brands")
                    Text("图片包含照片与服饰名称，不包含金额、备注、渠道或收纳位置。")
                        .font(.caption).foregroundStyle(.secondary)
                    if loading { ProgressView("正在生成分享图片…") }
                    if let error {
                        Text(error).foregroundStyle(.red)
                        Button("重新生成") { retry += 1 }
                    }
                    ForEach(files, id: \.self) { file in
                        LolitaShimmerImage(url: file, contentMode: .fit).accessibilityLabel("分享图片预览")
                    }

                }.padding(16)
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    #if os(iOS)
                    Button(files.count > 1 ? "分享 \(files.count) 张图片" : "分享图片") { sharing = true }
                        .buttonStyle(.borderedProminent).disabled(loading || files.isEmpty)
                        .accessibilityIdentifier("share-export")
                    #else
                    if !files.isEmpty { ShareLink(items: files) { Text("分享图片") } }
                    #endif
                }.padding(12).frame(maxWidth: .infinity).background(.regularMaterial)
            }
            .lolitaNavBar(title: "分享预览")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
            .task(id: generation) {
                loading = true; files = []; error = nil
                let content = ShareCardContent(title: title, images: images, items: items, brands: brands, showBrands: showBrands)
                do {
                    let rendered = try await ShareCardRenderer.render(content, skin: skinManager.current, dark: colorScheme == .dark)
                    try Task.checkCancellation(); files = rendered; loading = false
                } catch { if !Task.isCancelled { self.error = "分享图片生成失败，请重新生成。"; loading = false } }
            }
            #if os(iOS)
            .sheet(isPresented: $sharing) { ShareImageActivity(files: files) }
            #endif
        }
    }
}

#if os(iOS)
private struct ShareImageActivity: UIViewControllerRepresentable {
    let files: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: files, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif
