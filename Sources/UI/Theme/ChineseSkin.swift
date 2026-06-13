import SwiftUI

final class ChineseSkin: SkinProtocol {
    // Core colors
    let primaryColor = Color(red: 0.77, green: 0.12, blue: 0.23)      // #C41E3A
    let secondaryColor = Color(red: 0.85, green: 0.65, blue: 0.13)     // #DAA520
    let backgroundColor = Color(red: 1.0, green: 0.97, blue: 0.94)     // #FFF8F0
    let accentColor = Color(red: 0.77, green: 0.12, blue: 0.23)
    let cardColor = Color.white.opacity(0.92)

    // Dark mode
    let primaryColorDark = Color(red: 1.0, green: 0.42, blue: 0.42)    // #FF6B6B
    let secondaryColorDark = Color(red: 0.85, green: 0.65, blue: 0.13)
    let backgroundColorDark = Color(red: 0.10, green: 0.08, blue: 0.06) // #1A1410
    let accentColorDark = Color(red: 1.0, green: 0.42, blue: 0.42)
    let cardColorDark = Color(red: 0.18, green: 0.15, blue: 0.13).opacity(0.8) // #2D2520

    // Gradient
    let gradientColors: [Color] = [
        Color(red: 0.77, green: 0.12, blue: 0.23),
        Color(red: 0.85, green: 0.40, blue: 0.30)
    ]
    let gradientColorsDark: [Color] = [
        Color(red: 0.40, green: 0.10, blue: 0.15),
        Color(red: 0.25, green: 0.06, blue: 0.10)
    ]

    // Corner radii (CHINESE: 2/4/8)
    let cornerRadiusS: CGFloat = 2
    let cornerRadiusM: CGFloat = 4
    let cornerRadiusL: CGFloat = 8
    let buttonCornerRadius: CGFloat = 4

    // Spacing
    let spacingS: CGFloat = 4
    let spacingM: CGFloat = 8
    let spacingL: CGFloat = 16
    let spacingXL: CGFloat = 24

    // Card
    let cardElevation: CGFloat = 2
    let cardBorderStroke: (color: Color, width: CGFloat)? = nil
    let cardInnerPadding: CGFloat = 16
    let cardGap: CGFloat = 12

    // Top bar
    let topBarDecoration = "☁"
    let topBarDecorationAlpha: Double = 0.6
    let topBarBlurEnabled = false

    // Section
    var sectionAccentColor: Color { accentColor }
    let sectionAccentWidth: CGFloat = 3
    let sectionDividerColor = Color(red: 0.85, green: 0.65, blue: 0.13)

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
    let fontName: String? = "NotoSerifSC-Regular"
    let fontDisplayName = "Noto Serif SC"
}
