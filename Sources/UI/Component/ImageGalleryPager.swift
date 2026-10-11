import SwiftUI

struct ImageGalleryPager: View {
    @EnvironmentObject private var skinManager: SkinManager
    @Environment(\.colorScheme) private var colorScheme
    let urls: [URL]
    @State private var currentIndex = 0
    @State private var showFullscreen = false

    var body: some View {
        ImageFrame {
            Group {
                if urls.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "photo").font(.title2)
                        Text("暂无照片").font(.subheadline)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 112)
                    .background((colorScheme == .dark ? skinManager.current.accentColorDark : skinManager.current.accentColor).opacity(0.06))
                } else {
                    #if os(iOS)
                    TabView(selection: $currentIndex) {
                        ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                            LolitaShimmerImage(url: url)
                                .onTapGesture { showFullscreen = true }
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: urls.count > 1 ? .always : .never))
                    .aspectRatio(1, contentMode: .fit)
                    .fullScreenCover(isPresented: $showFullscreen) {
                        if urls.indices.contains(currentIndex) {
                            FullScreenImageViewer(url: urls[currentIndex])
                        }
                    }
                    #else
                    LolitaShimmerImage(url: urls.first)
                        .aspectRatio(1, contentMode: .fit)
                    #endif
                }
            }
        }
        .onChange(of: urls.count) { _, count in
            currentIndex = count == 0 ? 0 : min(currentIndex, count - 1)
        }
    }
}
