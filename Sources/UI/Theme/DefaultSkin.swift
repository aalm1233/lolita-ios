import SwiftUI

final class SweetSkin: SkinProtocol {
    // Core colors
    let primaryColor = Color(red: 1.0, green: 0.41, blue: 0.71)       // #FF69B4
    let secondaryColor = Color(red: 0.90, green: 0.90, blue: 0.98)     // #E6E6FA
    let backgroundColor = Color(red: 1.0, green: 0.94, blue: 0.97)     // #FFF0F5
    let accentColor = Color(red: 1.0, green: 0.41, blue: 0.71)
    let cardColor = Color.white.opacity(0.92)

    // Dark mode
    let primaryColorDark = Color(red: 0.91, green: 0.12, blue: 0.55)   // #E91E8C
    let secondaryColorDark = Color(red: 0.30, green: 0.25, blue: 0.35)
    let backgroundColorDark = Color(red: 0.10, green: 0.08, blue: 0.10)
    let accentColorDark = Color(red: 0.91, green: 0.12, blue: 0.55)
    let cardColorDark = Color(red: 0.20, green: 0.16, blue: 0.18).opacity(0.8)

    // Gradient
    let gradientColors: [Color] = [
        Color(red: 1.0, green: 0.41, blue: 0.71),
        Color(red: 0.94, green: 0.70, blue: 0.85)
    ]
    let gradientColorsDark: [Color] = [
        Color(red: 0.50, green: 0.10, blue: 0.30),
        Color(red: 0.30, green: 0.10, blue: 0.20)
    ]

    // Corner radii (matching Android DEFAULT: 8/16/24)
    let cornerRadiusS: CGFloat = 8
    let cornerRadiusM: CGFloat = 16
    let cornerRadiusL: CGFloat = 24
    let buttonCornerRadius: CGFloat = 16

    // Spacing (8pt grid)
    let spacingS: CGFloat = 4
    let spacingM: CGFloat = 8
    let spacingL: CGFloat = 16
    let spacingXL: CGFloat = 24

    // Card
    let cardElevation: CGFloat = 1
    let cardBorderStroke: (color: Color, width: CGFloat)? = nil
    let cardInnerPadding: CGFloat = 16
    let cardGap: CGFloat = 20

    // Top bar
    let topBarDecoration = "✿"
    let topBarDecorationAlpha: Double = 0.7
    let topBarBlurEnabled = true

    // Section
    var sectionAccentColor: Color { accentColor }
    let sectionAccentWidth: CGFloat = 3
    let sectionDividerColor = Color(red: 1.0, green: 0.75, blue: 0.80)

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
    let fontName: String? = nil
    let fontDisplayName = "系统默认"
}
