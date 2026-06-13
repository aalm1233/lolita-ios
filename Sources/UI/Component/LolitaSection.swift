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
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Rectangle()
                    .fill(accentColorResolved)
                    .frame(width: skinManager.current.sectionAccentWidth)
                    .cornerRadius(skinManager.current.sectionAccentWidth / 2)

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)

                Spacer()

                if let label = actionLabel {
                    Button(label) { onAction?() }
                        .font(.subheadline)
                        .foregroundColor(skinManager.current.accentColor)
                }
            }
            .padding(.horizontal, skinManager.current.spacingL)
            .padding(.vertical, skinManager.current.spacingM)

            Divider()
                .overlay(dividerColor)

            VStack(spacing: 0) { content() }
                .padding(.horizontal, skinManager.current.spacingL)
        }
    }
}
