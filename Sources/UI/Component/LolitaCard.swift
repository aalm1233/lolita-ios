import SwiftUI

enum CardVariant {
    case `default`
    case gallery
    case featured
    case compact
}

struct LolitaCard<Content: View>: View {
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var skinManager: SkinManager

    let variant: CardVariant
    @ViewBuilder let content: () -> Content

    init(variant: CardVariant = .default, @ViewBuilder content: @escaping () -> Content) {
        self.variant = variant
        self.content = content
    }

    private var isDark: Bool { colorScheme == .dark }

    private var currentBorder: (color: Color, width: CGFloat)? {
        if isDark, let dark = skinManager.current.cardBorderStrokeDark {
            return dark
        }
        return skinManager.current.cardBorderStroke
    }

    private var elevation: CGFloat {
        switch variant {
        case .default: return skinManager.current.cardElevation
        case .gallery: return skinManager.current.galleryCardElevation
        case .featured: return skinManager.current.featuredCardElevation
        case .compact: return skinManager.current.compactCardElevation
        }
    }

    private var padding: CGFloat {
        switch variant {
        case .default: return skinManager.current.cardInnerPadding
        case .gallery: return skinManager.current.galleryCardInnerPadding
        case .featured: return skinManager.current.featuredCardInnerPadding
        case .compact: return skinManager.current.compactCardInnerPadding
        }
    }

    private var cardBackground: Color {
        isDark ? skinManager.current.cardColorDark : skinManager.current.cardColor
    }

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: skinManager.current.cornerRadiusM)
                    .fill(cardBackground)
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
                radius: elevation,
                y: elevation * 0.5
            )
    }
}
