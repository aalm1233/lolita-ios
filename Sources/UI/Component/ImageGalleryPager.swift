@preconcurrency import SwiftUI

struct ImageGalleryPager: View {
    let urls: [URL]
    @State private var currentIndex: Int = 0
    @State private var showFullscreen: Bool = false

    var body: some View {
        VStack {
            if urls.isEmpty {
                Color.gray.opacity(0.1)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
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
                    FullScreenImageViewer(url: urls[currentIndex])
                }
#else
                LolitaShimmerImage(url: urls.first)
                    .aspectRatio(1, contentMode: .fit)
#endif
            }
        }
    }
}
