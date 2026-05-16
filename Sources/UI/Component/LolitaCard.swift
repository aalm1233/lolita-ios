import SwiftUI

enum CardVariant {
    case `default`
    case gallery
    case featured
    case compact
}

struct LolitaCard<Content: View>: View {
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var skin: DefaultSkin

    let variant: CardVariant
    @ViewBuilder let content: () -> Content

    init(variant: CardVariant = .default, @ViewBuilder content: @escaping () -> Content) {
        self.variant = variant
        self.content = content
    }

    private var isDark: Bool { colorScheme == .dark }

    private var elevation: CGFloat {
        switch variant {
        case .default: return skin.cardElevation
        case .gallery: return skin.galleryCardElevation
        case .featured: return skin.featuredCardElevation
        case .compact: return skin.compactCardElevation
        }
    }

    private var padding: CGFloat {
        switch variant {
        case .default: return skin.cardInnerPadding
        case .gallery: return skin.galleryCardInnerPadding
        case .featured: return skin.featuredCardInnerPadding
        case .compact: return skin.compactCardInnerPadding
        }
    }

    private var cardBackground: Color {
        isDark ? skin.cardColorDark : skin.cardColor
    }

    var body: some View {
        content()
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: skin.cornerRadiusM)
                    .fill(cardBackground)
            )
            .clipShape(RoundedRectangle(cornerRadius: skin.cornerRadiusM))
            .shadow(
                color: .black.opacity(0.08),
                radius: elevation,
                y: elevation * 0.5
            )
    }
}
