import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

final class SkinManager: ObservableObject {
    @Published var current: any SkinProtocol
    @Published var currentSkinType: SkinType = .default

    private let preferences = AppPreferences()

    init() {
        let storedType = SkinType(rawValue: preferences.skinType) ?? .default
        self.currentSkinType = storedType
        self.current = SkinManager.create(storedType)
    }

    func `switch`(to type: SkinType) {
        current = SkinManager.create(type)
        currentSkinType = type
        preferences.skinType = type.rawValue
    }

    var customFont: Font? {
        guard let name = current.fontName else { return nil }
        return Font.custom(name, size: UIFont.preferredFont(forTextStyle: .body).pointSize)
    }

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
