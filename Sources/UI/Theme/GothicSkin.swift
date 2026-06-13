import SwiftUI

final class GothicSkin: SkinProtocol {
    // Core colors
    let primaryColor = Color(red: 0.29, green: 0.05, blue: 0.31)      // #4A0E4E
    let secondaryColor = Color(red: 0.55, green: 0.0, blue: 0.0)       // #8B0000
    let backgroundColor = Color(red: 0.96, green: 0.94, blue: 0.96)    // #F5F0F5
    let accentColor = Color(red: 0.29, green: 0.05, blue: 0.31)
    let cardColor = Color.white.opacity(0.92)

    // Dark mode
    let primaryColorDark = Color(red: 0.73, green: 0.53, blue: 0.99)   // #BB86FC
    let secondaryColorDark = Color(red: 0.60, green: 0.20, blue: 0.25)
    let backgroundColorDark = Color(red: 0.10, green: 0.10, blue: 0.18) // #1A1A2E
    let accentColorDark = Color(red: 0.73, green: 0.53, blue: 0.99)
    let cardColorDark = Color(red: 0.18, green: 0.18, blue: 0.27).opacity(0.8) // #2D2D44

    // Gradient
    let gradientColors: [Color] = [
        Color(red: 0.29, green: 0.05, blue: 0.31),
        Color(red: 0.20, green: 0.02, blue: 0.22)
    ]
    let gradientColorsDark: [Color] = [
        Color(red: 0.15, green: 0.08, blue: 0.18),
        Color(red: 0.08, green: 0.04, blue: 0.10)
    ]

    // Corner radii (GOTHIC: 4/8/12)
    let cornerRadiusS: CGFloat = 4
    let cornerRadiusM: CGFloat = 8
    let cornerRadiusL: CGFloat = 12
    let buttonCornerRadius: CGFloat = 6

    // Spacing
    let spacingS: CGFloat = 4
    let spacingM: CGFloat = 8
    let spacingL: CGFloat = 16
    let spacingXL: CGFloat = 24

    // Card
    let cardElevation: CGFloat = 2
    let cardBorderStroke: (color: Color, width: CGFloat)? = nil
    let cardInnerPadding: CGFloat = 14
    let cardGap: CGFloat = 16

    // Top bar
    let topBarDecoration = "✝"
    let topBarDecorationAlpha: Double = 0.5
    let topBarBlurEnabled = false

    // Section
    var sectionAccentColor: Color { accentColor }
    let sectionAccentWidth: CGFloat = 2
    let sectionDividerColor = Color(red: 0.35, green: 0.10, blue: 0.35)

    // Gallery card
    let galleryCardElevation: CGFloat = 0
    let galleryCardInnerPadding: CGFloat = 0

    // Featured card
    let featuredCardElevation: CGFloat = 3
    let featuredCardInnerPadding: CGFloat = 20

    // Compact card
    let compactCardElevation: CGFloat = 1
    let compactCardInnerPadding: CGFloat = 8

    // Font
    let fontName: String? = "Cinzel-Regular"
    let fontDisplayName = "Cinzel"
}
