import SwiftUI
import Kingfisher

struct ImageGalleryPager: View {
    @EnvironmentObject private var skinManager: SkinManager
    @Environment(\.colorScheme) private var colorScheme
    let urls: [URL]
    var emptyTitle = "暂无照片"
    @State private var currentIndex = 0
    @State private var showFullscreen = false
    @State private var imageRatios: [URL: CGFloat] = [:]

    private var aspectRatio: CGFloat {
        guard urls.indices.contains(currentIndex) else { return 1 }
        return imageRatios[urls[currentIndex]] ?? 0.8
    }

    var body: some View {
        VStack(spacing: 8) {
            ImageFrame {
                if urls.isEmpty {
                    HStack(spacing: 10) {
                        SkinIcon(systemName: "photo", size: 22)
                        Text(emptyTitle).font(.subheadline)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 112)
                    .background((colorScheme == .dark ? skinManager.current.accentColorDark : skinManager.current.accentColor).opacity(0.06))
                } else {
                    #if os(iOS)
                    // PageTabView needs a finite height inside a lazy scrolling stack.
                    // Derive it from the available width, without feeding its intrinsic
                    // size back into the enclosing scroll view's layout.
                    GeometryReader { geometry in
                        TabView(selection: $currentIndex) {
                            ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                                galleryImage(url)
                                    .contentShape(Rectangle())
                                    .onTapGesture { showFullscreen = true }
                                    .accessibilityLabel("第\(index + 1)张照片")
                                    .accessibilityHint("轻点查看原图")
                                    .tag(index)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                    .aspectRatio(aspectRatio, contentMode: .fit)
                    .fullScreenCover(isPresented: $showFullscreen) {
                        FullScreenImageViewer(urls: urls, initialIndex: currentIndex)
                    }
                    #else
                    galleryImage(urls[urls.indices.contains(currentIndex) ? currentIndex : 0])
                        .aspectRatio(aspectRatio, contentMode: .fit)
                    #endif
                }
            }
            .frame(maxWidth: .infinity)
            if urls.count > 1 {
                HStack(spacing: 10) {
                    Text("\(currentIndex + 1) / \(urls.count)").font(.caption).monospacedDigit()
                    Text("左右滑动查看照片").font(.caption).foregroundStyle(.secondary)
                }.foregroundStyle(.secondary)
            }
        }
        .onChange(of: urls) { _, value in
            currentIndex = value.isEmpty ? 0 : min(currentIndex, value.count - 1)
            imageRatios = imageRatios.filter { value.contains($0.key) }
        }
    }

    private func galleryImage(_ url: URL) -> some View {
        KFImage(url)
            .onSuccess { result in
                let size = result.image.size
                if size.width > 0, size.height > 0 {
                    let ratio = size.width / size.height
                    if imageRatios[url] != ratio { imageRatios[url] = ratio }
                }
            }
            .placeholder {
                RoundedRectangle(cornerRadius: skinManager.current.cornerRadiusM)
                    .fill((colorScheme == .dark ? skinManager.current.cardColorDark : skinManager.current.cardColor))
                    .overlay { ProgressView() }
            }
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(colorScheme == .dark ? skinManager.current.cardColorDark : skinManager.current.cardColor)
    }
}
