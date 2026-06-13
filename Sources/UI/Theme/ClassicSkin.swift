import SwiftUI

final class ClassicSkin: SkinProtocol {
    // Core colors
    let primaryColor = Color(red: 0.45, green: 0.18, blue: 0.22)      // #722F37
    let secondaryColor = Color(red: 0.55, green: 0.27, blue: 0.07)     // #8B4513
    let backgroundColor = Color(red: 0.98, green: 0.96, blue: 0.94)    // #FAF5F0
    let accentColor = Color(red: 0.45, green: 0.18, blue: 0.22)
    let cardColor = Color.white.opacity(0.92)

    // Dark mode
    let primaryColorDark = Color(red: 0.77, green: 0.56, blue: 0.60)   // #C49098
    let secondaryColorDark = Color(red: 0.65, green: 0.40, blue: 0.20)
    let backgroundColorDark = Color(red: 0.10, green: 0.08, blue: 0.08) // #1A1515
    let accentColorDark = Color(red: 0.77, green: 0.56, blue: 0.60)
    let cardColorDark = Color(red: 0.18, green: 0.15, blue: 0.15).opacity(0.8) // #2D2525

    // Gradient
    let gradientColors: [Color] = [
        Color(red: 0.45, green: 0.18, blue: 0.22),
        Color(red: 0.55, green: 0.27, blue: 0.20)
    ]
    let gradientColorsDark: [Color] = [
        Color(red: 0.25, green: 0.10, blue: 0.12),
        Color(red: 0.15, green: 0.06, blue: 0.08)
    ]

    // Corner radii (CLASSIC: 6/12/16)
    let cornerRadiusS: CGFloat = 6
    let cornerRadiusM: CGFloat = 12
    let cornerRadiusL: CGFloat = 16
    let buttonCornerRadius: CGFloat = 8

    // Spacing
    let spacingS: CGFloat = 4
    let spacingM: CGFloat = 8
    let spacingL: CGFloat = 16
    let spacingXL: CGFloat = 24

    // Card
    let cardElevation: CGFloat = 2
    let cardBorderStroke: (color: Color, width: CGFloat)? = nil
    let cardInnerPadding: CGFloat = 16
    let cardGap: CGFloat = 16

    // Top bar
    let topBarDecoration = "♠"
    let topBarDecorationAlpha: Double = 0.5
    let topBarBlurEnabled = false

    // Section
    var sectionAccentColor: Color { accentColor }
    let sectionAccentWidth: CGFloat = 3
    let sectionDividerColor = Color(red: 0.55, green: 0.27, blue: 0.07)

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
    let fontName: String? = "PlayfairDisplay-Regular"
    let fontDisplayName = "Playfair Display"
}
