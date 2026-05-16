import SwiftUI

struct LolitaSection<Content: View>: View {
    @EnvironmentObject var skin: DefaultSkin

    let title: String
    var actionLabel: String? = nil
    var onAction: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Rectangle()
                    .fill(skin.sectionAccentColor)
                    .frame(width: skin.sectionAccentWidth)
                    .cornerRadius(skin.sectionAccentWidth / 2)

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)

                Spacer()

                if let label = actionLabel {
                    Button(label) { onAction?() }
                        .font(.subheadline)
                        .foregroundColor(skin.accentColor)
                }
            }
            .padding(.horizontal, skin.spacingL)
            .padding(.vertical, skin.spacingM)

            Divider()

            VStack(spacing: 0) { content() }
                .padding(.horizontal, skin.spacingL)
        }
    }
}
