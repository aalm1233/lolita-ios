import SwiftUI

final class VictorianSkin: SkinProtocol {
    // Core colors
    let primaryColor = Color(red: 0.48, green: 0.12, blue: 0.23)      // #7B1E3A
    let secondaryColor = Color(red: 0.72, green: 0.53, blue: 0.04)     // #B8860B
    let backgroundColor = Color(red: 1.0, green: 0.97, blue: 0.94)     // #FFF8F0
    let accentColor = Color(red: 0.48, green: 0.12, blue: 0.23)
    let cardColor = Color.white.opacity(0.92)

    // Dark mode
    let primaryColorDark = Color(red: 0.77, green: 0.56, blue: 0.60)   // #C49098
    let secondaryColorDark = Color(red: 0.72, green: 0.53, blue: 0.04)
    let backgroundColorDark = Color(red: 0.10, green: 0.07, blue: 0.06) // #1A1210
    let accentColorDark = Color(red: 0.77, green: 0.56, blue: 0.60)
    let cardColorDark = Color(red: 0.17, green: 0.12, blue: 0.09).opacity(0.8) // #2C1E18

    // Gradient
    let gradientColors: [Color] = [
        Color(red: 0.48, green: 0.12, blue: 0.23),
        Color(red: 0.60, green: 0.25, blue: 0.30)
    ]
    let gradientColorsDark: [Color] = [
        Color(red: 0.25, green: 0.08, blue: 0.12),
        Color(red: 0.15, green: 0.05, blue: 0.08)
    ]

    // Corner radii (VICTORIAN: 6/12/16)
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
    let cardElevation: CGFloat = 3
    let cardBorderStroke: (color: Color, width: CGFloat)? = (Color(red: 0.72, green: 0.53, blue: 0.04), 1) // gold 1pt
    let cardBorderStrokeDark: (color: Color, width: CGFloat)? = (Color(red: 0.72, green: 0.53, blue: 0.04), 0.5) // gold 0.5pt
    let cardInnerPadding: CGFloat = 16
    let cardGap: CGFloat = 20

    // Top bar
    let topBarDecoration = "⚜"
    let topBarDecorationAlpha: Double = 0.5
    let topBarBlurEnabled = false

    // Section
    var sectionAccentColor: Color { accentColor }
    let sectionAccentWidth: CGFloat = 3
    let sectionDividerColor = Color(red: 0.72, green: 0.53, blue: 0.04)

    // Image frame
    let imageFrameBorderStroke: (color: Color, width: CGFloat)? = (Color(red: 0.72, green: 0.53, blue: 0.04), 1)
    let imageFrameBorderStrokeDark: (color: Color, width: CGFloat)? = (Color(red: 0.72, green: 0.53, blue: 0.04), 0.5)

    // Gallery card
    let galleryCardElevation: CGFloat = 0
    let galleryCardInnerPadding: CGFloat = 0

    // Featured card
    let featuredCardElevation: CGFloat = 4
    let featuredCardInnerPadding: CGFloat = 24

    // Compact card
    let compactCardElevation: CGFloat = 1
    let compactCardInnerPadding: CGFloat = 10

    // Font
    let fontName: String? = "CormorantGaramond-Regular"
    let fontDisplayName = "Cormorant Garamond"
}
