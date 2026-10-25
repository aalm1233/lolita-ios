import SwiftUI
import CoreText
#if canImport(UIKit)
import UIKit
#endif

final class SkinManager: ObservableObject {
    @Published var current: any SkinProtocol
    @Published var currentSkinType: SkinType = .default

    private let preferences = AppPreferences()

    init() {
        _ = Self.fontsRegistered
        let storedType = SkinType(rawValue: preferences.skinType) ?? .default
        self.currentSkinType = storedType
        self.current = SkinManager.create(storedType)
    }

    func `switch`(to type: SkinType) {
        current = SkinManager.create(type)
        currentSkinType = type
        preferences.skinType = type.rawValue
    }

    /// Decorative faces are scoped to headings. Controls and money inherit the system face.
    func headingFont(size: CGFloat, relativeTo style: Font.TextStyle = .headline) -> Font {
        guard let name = current.fontName else { return .system(style, design: .default).weight(.semibold) }
        return .custom(name, size: size, relativeTo: style)
    }

    private static let fontsRegistered: Void = {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        for name in ["cinzel_regular", "noto_serif_sc_regular", "playfair_display_regular", "pacifico_regular", "cormorant_garamond"] {
            if let url = bundle.url(forResource: name, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
        #endif
    }()

    static func create(_ type: SkinType) -> any SkinProtocol {
        switch type {
        case .default: return SweetSkin()
        case .gothic: return GothicSkin()
        case .chinese: return ChineseSkin()
        case .classic: return ClassicSkin()
        case .navy: return NavySkin()
        case .country: return CountrySkin()
        case .victorian: return VictorianSkin()
        }
    }
}
