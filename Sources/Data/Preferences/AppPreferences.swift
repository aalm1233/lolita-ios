import Foundation

final class AppPreferences {
    private let defaults = UserDefaults.standard

    var isFirstLaunch: Bool {
        get { defaults.object(forKey: "isFirstLaunch") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "isFirstLaunch") }
    }

    var skinType: String {
        get { defaults.string(forKey: "skin_type") ?? "DEFAULT" }
        set { defaults.set(newValue, forKey: "skin_type") }
    }
}
