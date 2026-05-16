import Foundation

final class AppPreferences {
    private let defaults = UserDefaults.standard

    var isFirstLaunch: Bool {
        get { defaults.object(forKey: "isFirstLaunch") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "isFirstLaunch") }
    }

    var currentSkinType: String {
        get { defaults.string(forKey: "currentSkinType") ?? "DEFAULT" }
        set { defaults.set(newValue, forKey: "currentSkinType") }
    }
}
