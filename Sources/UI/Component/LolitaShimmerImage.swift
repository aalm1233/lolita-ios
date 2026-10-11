import SwiftUI
import Kingfisher

struct LolitaShimmerImage: View {
    let url: URL?
    var contentMode: SwiftUI.ContentMode = .fill

    var body: some View {
        KFImage(url)
            .placeholder {
                ZStack {
                    Color.gray.opacity(0.15)
                    ProgressView()
                        .tint(.gray)
                }
                .shimmer()
            }
            .fade(duration: 0.3)
            .resizable()
            .aspectRatio(contentMode: contentMode)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
