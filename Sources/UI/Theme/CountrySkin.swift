import SwiftUI

final class CountrySkin: SkinProtocol {
    // Core colors
    let primaryColor = Color(red: 0.49, green: 0.60, blue: 0.41)      // #7C9A69
    let secondaryColor = Color(red: 0.77, green: 0.40, blue: 0.35)     // #C56759
    let backgroundColor = Color(red: 0.98, green: 0.96, blue: 0.91)    // #F9F4E8
    let accentColor = Color(red: 0.49, green: 0.60, blue: 0.41)
    let cardColor = Color.white.opacity(0.92)

    // Dark mode
    let primaryColorDark = Color(red: 0.66, green: 0.79, blue: 0.60)   // #A8C99A
    let secondaryColorDark = Color(red: 0.77, green: 0.40, blue: 0.35)
    let backgroundColorDark = Color(red: 0.12, green: 0.15, blue: 0.11) // #1F261C
    let accentColorDark = Color(red: 0.66, green: 0.79, blue: 0.60)
    let cardColorDark = Color(red: 0.18, green: 0.21, blue: 0.16).opacity(0.8) // #2D3529

    // Gradient
    let gradientColors: [Color] = [
        Color(red: 0.49, green: 0.60, blue: 0.41),
        Color(red: 0.65, green: 0.75, blue: 0.55)
    ]
    let gradientColorsDark: [Color] = [
        Color(red: 0.20, green: 0.28, blue: 0.15),
        Color(red: 0.12, green: 0.18, blue: 0.10)
    ]

    // Corner radii (COUNTRY: 10/20/28)
    let cornerRadiusS: CGFloat = 10
    let cornerRadiusM: CGFloat = 20
    let cornerRadiusL: CGFloat = 28
    let buttonCornerRadius: CGFloat = 18

    // Spacing
    let spacingS: CGFloat = 4
    let spacingM: CGFloat = 8
    let spacingL: CGFloat = 16
    let spacingXL: CGFloat = 24

    // Card
    let cardElevation: CGFloat = 1
    let cardBorderStroke: (color: Color, width: CGFloat)? = nil
    let cardInnerPadding: CGFloat = 18
    let cardGap: CGFloat = 14

    // Top bar
    let topBarDecoration = "✿"
    let topBarDecorationAlpha: Double = 0.7
    let topBarBlurEnabled = false

    // Section
    var sectionAccentColor: Color { accentColor }
    let sectionAccentWidth: CGFloat = 3
    let sectionDividerColor = Color(red: 0.49, green: 0.60, blue: 0.41)

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
    let fontName: String? = "CormorantGaramond-Regular"
    let fontDisplayName = "Cormorant Garamond"
}
