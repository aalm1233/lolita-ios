import SwiftUI

struct ImageFrame<Content: View>: View {
    @EnvironmentObject var skinManager: SkinManager
    @Environment(\.colorScheme) var colorScheme

    @ViewBuilder let content: () -> Content

    private var isDark: Bool { colorScheme == .dark }

    private var currentBorder: (color: Color, width: CGFloat)? {
        if isDark, let dark = skinManager.current.imageFrameBorderStrokeDark {
            return dark
        }
        return skinManager.current.imageFrameBorderStroke
    }

    var body: some View {
        content()
            .padding(skinManager.current.imageFramePadding)
            .background(
                RoundedRectangle(cornerRadius: skinManager.current.cornerRadiusM)
                    .fill(Color.clear)
            )
            .overlay(
                Group {
                    if let border = currentBorder {
                        RoundedRectangle(cornerRadius: skinManager.current.cornerRadiusM)
                            .stroke(border.color, lineWidth: border.width)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: skinManager.current.cornerRadiusM))
            .shadow(
                color: .black.opacity(0.08),
                radius: skinManager.current.imageFrameElevation,
                y: skinManager.current.imageFrameElevation * 0.5
            )
    }
}
