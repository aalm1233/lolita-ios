import SwiftUI

protocol SkinProtocol: AnyObject, ObservableObject {
    // Core colors
    var primaryColor: Color { get }
    var secondaryColor: Color { get }
    var backgroundColor: Color { get }
    var accentColor: Color { get }
    var cardColor: Color { get }

    // Dark mode variants
    var primaryColorDark: Color { get }
    var secondaryColorDark: Color { get }
    var backgroundColorDark: Color { get }
    var accentColorDark: Color { get }
    var cardColorDark: Color { get }

    // Gradient
    var gradientColors: [Color] { get }
    var gradientColorsDark: [Color] { get }

    // Corner radii
    var cornerRadiusS: CGFloat { get }
    var cornerRadiusM: CGFloat { get }
    var cornerRadiusL: CGFloat { get }

    // Spacing
    var spacingS: CGFloat { get }
    var spacingM: CGFloat { get }
    var spacingL: CGFloat { get }
    var spacingXL: CGFloat { get }

    // Card
    var cardElevation: CGFloat { get }
    var cardBorderStroke: (color: Color, width: CGFloat)? { get }
    var cardInnerPadding: CGFloat { get }
    var cardGap: CGFloat { get }

    // Top bar
    var topBarDecoration: String { get }
    var topBarDecorationAlpha: Double { get }
    var topBarBlurEnabled: Bool { get }

    // Section
    var sectionAccentColor: Color { get }
    var sectionAccentWidth: CGFloat { get }
    var sectionDividerColor: Color { get }

    // Gallery variant card
    var galleryCardElevation: CGFloat { get }
    var galleryCardInnerPadding: CGFloat { get }

    // Featured variant card
    var featuredCardElevation: CGFloat { get }
    var featuredCardInnerPadding: CGFloat { get }

    // Compact variant card
    var compactCardElevation: CGFloat { get }
    var compactCardInnerPadding: CGFloat { get }
}
