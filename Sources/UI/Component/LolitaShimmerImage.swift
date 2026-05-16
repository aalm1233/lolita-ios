import SwiftUI
import Kingfisher

struct LolitaShimmerImage: View {
    let url: URL?
    var aspectRatio: CGFloat = 1.0

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
            .scaledToFill()
            .aspectRatio(aspectRatio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
