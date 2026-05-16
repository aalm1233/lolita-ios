import SwiftUI

@main
struct LolitaApp: App {
    @StateObject private var skin = DefaultSkin()

    var body: some Scene {
        WindowGroup {
            // Placeholder until navigation is built
            Text("Lolita iOS")
                .environmentObject(skin as SkinProtocol)
        }
    }
}
