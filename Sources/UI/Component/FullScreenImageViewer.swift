import SwiftUI
import Kingfisher

struct GalleryImageEntry: Sendable {
    let itemId: Int64
    let title: String
    let brandName: String?
    let url: URL
}

struct FullScreenImageViewer: View {
    @Environment(\.dismiss) private var dismiss
    let urls: [URL]
    private let galleryEntries: [GalleryImageEntry]
    private let onShowDetails: ((Int64) -> Void)?
    @State private var currentIndex: Int

    init(url: URL) { self.init(urls: [url], initialIndex: 0) }
    init(urls: [URL], initialIndex: Int = 0) {
        self.urls = urls
        galleryEntries = []
        onShowDetails = nil
        _currentIndex = State(initialValue: urls.isEmpty ? 0 : min(max(0, initialIndex), urls.count - 1))
    }

    init(galleryEntries: [GalleryImageEntry], initialIndex: Int = 0, onShowDetails: @escaping (Int64) -> Void) {
        self.galleryEntries = galleryEntries
        urls = galleryEntries.map(\.url)
        self.onShowDetails = onShowDetails
        _currentIndex = State(initialValue: galleryEntries.isEmpty ? 0 : min(max(0, initialIndex), galleryEntries.count - 1))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            #if os(iOS)
            TabView(selection: $currentIndex) {
                ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                    DetailZoomableImage(url: url).tag(index)
                }
            }.tabViewStyle(.page(indexDisplayMode: .never))
            #else
            if urls.indices.contains(currentIndex) { DetailZoomableImage(url: urls[currentIndex]) }
            #endif
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.5), in: Circle())
            }.padding(16).accessibilityLabel("关闭照片")
        }
        .overlay(alignment: .bottom) {
            if galleryEntries.indices.contains(currentIndex) {
                let entry = galleryEntries[currentIndex]
                Button { onShowDetails?(entry.itemId) } label: {
                    VStack(spacing: 5) {
                        Text(entry.title).font(.headline).lineLimit(2)
                        if let brand = entry.brandName { Text(brand).font(.subheadline).foregroundStyle(.white.opacity(0.75)) }
                        Text("点击查看详情 · \(currentIndex + 1) / \(urls.count)").font(.caption).foregroundStyle(.white.opacity(0.65))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .background(.black.opacity(0.6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("查看\(entry.title)的服饰详情")
            } else {
                VStack(spacing: 6) {
                    if urls.count > 1 { Text("\(currentIndex + 1) / \(urls.count)").font(.subheadline).monospacedDigit() }
                    Text("双击放大 · 双指缩放").font(.caption)
                }
                .foregroundStyle(.white.opacity(0.85))
                .padding(12)
                .background(.black.opacity(0.45), in: Capsule())
                .padding(.bottom, 12)
                .allowsHitTesting(false)
            }
        }
    }
}

private struct DetailZoomableImage: View {
    let url: URL
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            KFImage(url)
                .placeholder { ProgressView().tint(.white) }
                .resizable()
                .scaledToFit()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(MagnificationGesture()
                    .onChanged { value in scale = min(5, max(1, lastScale * value)) }
                    .onEnded { _ in
                        lastScale = scale
                        offset = bounded(offset, in: geometry.size)
                        lastOffset = offset
                    })
                .simultaneousGesture(DragGesture()
                    .onChanged { value in
                        offset = bounded(CGSize(width: lastOffset.width + value.translation.width,
                                                height: lastOffset.height + value.translation.height), in: geometry.size)
                    }
                    .onEnded { _ in lastOffset = offset }, including: scale > 1 ? .all : .none)
                .onTapGesture(count: 2) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        scale = scale > 1 ? 1 : 2
                        lastScale = scale
                        offset = .zero
                        lastOffset = .zero
                    }
                }
                .accessibilityLabel("照片")
                .accessibilityHint("双击或双指缩放查看细节")
        }
    }

    private func bounded(_ value: CGSize, in size: CGSize) -> CGSize {
        let limitX = size.width * (scale - 1) / 2
        let limitY = size.height * (scale - 1) / 2
        return CGSize(width: min(limitX, max(-limitX, value.width)), height: min(limitY, max(-limitY, value.height)))
    }
}
