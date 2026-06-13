import SwiftUI

enum SkinType: String, CaseIterable {
    case `default` = "DEFAULT"
    case gothic = "GOTHIC"
    case chinese = "CHINESE"
    case classic = "CLASSIC"
    case navy = "NAVY"
    case country = "COUNTRY"
    case victorian = "VICTORIAN"

    var displayName: String {
        switch self {
        case .default: return "甜美粉"
        case .gothic: return "哥特暗黑"
        case .chinese: return "中华风韵"
        case .classic: return "经典优雅"
        case .navy: return "清风水手"
        case .country: return "田园牧歌"
        case .victorian: return "维多利亚"
        }
    }
}

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

    // Font
    var fontName: String? { get }
    var fontDisplayName: String { get }

    // Image frame
    var imageFrameElevation: CGFloat { get }
    var imageFrameBorderStroke: (color: Color, width: CGFloat)? { get }
    var imageFrameBorderStrokeDark: (color: Color, width: CGFloat)? { get }
    var imageFramePadding: CGFloat { get }

    // Dark mode borders
    var cardBorderStrokeDark: (color: Color, width: CGFloat)? { get }
    var sectionDividerColorDark: Color { get }
    var sectionAccentColorDark: Color { get }

    // Shapes
    var buttonCornerRadius: CGFloat { get }

    // Blur
    var navBarBlurEnabled: Bool { get }
    var dialogBlurEnabled: Bool { get }

    // Tab bar
    var tabBarBackgroundColor: Color { get }
    var tabBarBackgroundColorDark: Color { get }
}

extension SkinProtocol {
    var fontName: String? { nil }
    var fontDisplayName: String { "系统默认" }

    var imageFrameElevation: CGFloat { 2 }
    var imageFrameBorderStroke: (color: Color, width: CGFloat)? { nil }
    var imageFrameBorderStrokeDark: (color: Color, width: CGFloat)? { nil }
    var imageFramePadding: CGFloat { 0 }

    var cardBorderStrokeDark: (color: Color, width: CGFloat)? { nil }
    var sectionDividerColorDark: Color { sectionDividerColor }
    var sectionAccentColorDark: Color { sectionAccentColor }

    var buttonCornerRadius: CGFloat { cornerRadiusM }

    var navBarBlurEnabled: Bool { false }
    var dialogBlurEnabled: Bool { false }

    var tabBarBackgroundColor: Color { cardColor }
    var tabBarBackgroundColorDark: Color { cardColorDark }
}
