import SwiftUI

final class NavySkin: SkinProtocol {
    // Core colors
    let primaryColor = Color(red: 0.29, green: 0.56, blue: 0.85)      // #4A90D9
    let secondaryColor = Color(red: 0.85, green: 0.65, blue: 0.13)     // #DAA520
    let backgroundColor = Color(red: 0.94, green: 0.97, blue: 1.0)     // #F0F8FF
    let accentColor = Color(red: 0.29, green: 0.56, blue: 0.85)
    let cardColor = Color.white.opacity(0.92)

    // Dark mode
    let primaryColorDark = Color(red: 0.48, green: 0.72, blue: 0.96)   // #7AB8F5
    let secondaryColorDark = Color(red: 0.85, green: 0.65, blue: 0.13)
    let backgroundColorDark = Color(red: 0.05, green: 0.11, blue: 0.16) // #0D1B2A
    let accentColorDark = Color(red: 0.48, green: 0.72, blue: 0.96)
    let cardColorDark = Color(red: 0.11, green: 0.18, blue: 0.27).opacity(0.8) // #1B2D44

    // Gradient
    let gradientColors: [Color] = [
        Color(red: 0.29, green: 0.56, blue: 0.85),
        Color(red: 0.45, green: 0.70, blue: 0.90)
    ]
    let gradientColorsDark: [Color] = [
        Color(red: 0.10, green: 0.25, blue: 0.45),
        Color(red: 0.05, green: 0.15, blue: 0.30)
    ]

    // Corner radii (NAVY: 7/14/20)
    let cornerRadiusS: CGFloat = 7
    let cornerRadiusM: CGFloat = 14
    let cornerRadiusL: CGFloat = 20
    let buttonCornerRadius: CGFloat = 14

    // Spacing
    let spacingS: CGFloat = 4
    let spacingM: CGFloat = 8
    let spacingL: CGFloat = 16
    let spacingXL: CGFloat = 24

    // Card
    let cardElevation: CGFloat = 1.5
    let cardBorderStroke: (color: Color, width: CGFloat)? = nil
    let cardInnerPadding: CGFloat = 16
    let cardGap: CGFloat = 18

    // Top bar
    let topBarDecoration = "⚓"
    let topBarDecorationAlpha: Double = 0.6
    let topBarBlurEnabled = false

    // Section
    var sectionAccentColor: Color { accentColor }
    let sectionAccentWidth: CGFloat = 3
    let sectionDividerColor = Color(red: 0.29, green: 0.56, blue: 0.85)

    // Gallery card
    let galleryCardElevation: CGFloat = 0
    let galleryCardInnerPadding: CGFloat = 0

    // Featured card
    let featuredCardElevation: CGFloat = 2
    let featuredCardInnerPadding: CGFloat = 20

    // Compact card
    let compactCardElevation: CGFloat = 0.5
    let compactCardInnerPadding: CGFloat = 8

    // Font
    let fontName: String? = "Pacifico-Regular"
    let fontDisplayName = "Pacifico"
}
