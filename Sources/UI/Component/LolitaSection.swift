import SwiftUI

struct LolitaSection<Content: View>: View {
    @EnvironmentObject var skinManager: SkinManager
    @Environment(\.colorScheme) var colorScheme

    let title: String
    var actionLabel: String? = nil
    var onAction: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    private var isDark: Bool { colorScheme == .dark }

    private var dividerColor: Color {
        isDark ? skinManager.current.sectionDividerColorDark : skinManager.current.sectionDividerColor
    }

    private var accentColorResolved: Color {
        isDark ? skinManager.current.sectionAccentColorDark : skinManager.current.sectionAccentColor
    }

    var body: some View {
        LolitaCard(variant: .gallery) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Rectangle()
                        .fill(accentColorResolved)
                        .frame(width: skinManager.current.sectionAccentWidth, height: 18)
                        .cornerRadius(skinManager.current.sectionAccentWidth / 2)

                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)

                    Spacer()

                    if let label = actionLabel {
                        Button(label) { onAction?() }
                            .font(.subheadline)
                            .foregroundColor(accentColorResolved)
                    }
                }
                .padding(.horizontal, skinManager.current.spacingL)
                .padding(.vertical, skinManager.current.spacingM)

                Divider()
                    .overlay(dividerColor)

                VStack(alignment: .leading, spacing: skinManager.current.spacingM) { content() }
                    .padding(.horizontal, skinManager.current.spacingL)
                    .padding(.vertical, skinManager.current.spacingM)
            }
        }
    }
}
